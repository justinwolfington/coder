package database_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/coder/coder/v2/testutil"
)

// This file owns the deterministic lock-race harness shared by the
// soft-delete guard tests and the agent memory tests; it belongs to neither
// feature.

// stmt pairs a SQL statement with its bound arguments for runLockRace.
type stmt struct {
	sql  string
	args []any
}

// waitForBackendBlocked polls pg_stat_activity until the backend identified by
// pid is waiting on a heavyweight lock, proving the racing statement is
// blocked on a row lock rather than still executing.
func waitForBackendBlocked(ctx context.Context, t *testing.T, sqlDB *sql.DB, pid int) {
	t.Helper()
	testutil.Eventually(ctx, t, func(ctx context.Context) bool {
		var lockWaits int
		err := sqlDB.QueryRowContext(ctx, `
			SELECT count(*)
			FROM pg_stat_activity
			WHERE pid = $1 AND wait_event_type = 'Lock'
		`, pid).Scan(&lockWaits)
		return err == nil && lockWaits == 1
	}, testutil.IntervalFast, "wait for the backend to block on a row lock")
	require.NoError(t, ctx.Err(), "waiting for the blocked backend")
}

// lockTimeoutConn returns a dedicated connection whose lock_timeout bounds
// every lock wait, so a statement that unexpectedly blocks fails the test
// instead of waiting for the shared context deadline to release the lock
// (which would let the statement succeed and mask the regression). The
// timeout is RESET before the connection returns to the pool: database/sql
// does not reset session state, and cleanups run LIFO, so the RESET runs
// before Close.
func lockTimeoutConn(ctx context.Context, t *testing.T, sqlDB *sql.DB, timeout string) *sql.Conn {
	t.Helper()
	conn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = conn.Close() })
	_, err = conn.ExecContext(ctx, `SET lock_timeout = '`+timeout+`'`)
	require.NoError(t, err)
	t.Cleanup(func() { _, _ = conn.ExecContext(context.Background(), `RESET lock_timeout`) })
	return conn
}

// runLockRace executes the blocking statements in one transaction at the
// given isolation level, launches racing in its own transaction (same
// isolation) on a dedicated connection, deterministically waits for it to
// block on a row lock held by the blocking transaction, executes
// beforeCommit inside the blocking transaction, commits it, commits the
// racing transaction when its statement succeeded, and returns the racing
// side's error. Pass sql.LevelDefault for the ordinary READ COMMITTED race.
func runLockRace(ctx context.Context, t *testing.T, sqlDB *sql.DB, isolation sql.IsolationLevel, blocking []stmt, racing stmt, beforeCommit []stmt) error {
	t.Helper()

	blockTx, err := sqlDB.BeginTx(ctx, &sql.TxOptions{Isolation: isolation})
	require.NoError(t, err)
	committed := false
	t.Cleanup(func() {
		if !committed {
			_ = blockTx.Rollback()
		}
	})
	for _, s := range blocking {
		_, err := blockTx.ExecContext(ctx, s.sql, s.args...)
		require.NoError(t, err)
	}

	raceConn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = raceConn.Close() })

	var racePID int
	require.NoError(t, raceConn.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&racePID))

	raceTx, err := raceConn.BeginTx(ctx, &sql.TxOptions{Isolation: isolation})
	require.NoError(t, err)
	t.Cleanup(func() { _ = raceTx.Rollback() })

	raceResult := make(chan error, 1)
	go func() {
		_, err := raceTx.ExecContext(ctx, racing.sql, racing.args...)
		if err == nil {
			err = raceTx.Commit()
		}
		raceResult <- err
	}()

	waitForBackendBlocked(ctx, t, sqlDB, racePID)

	for _, s := range beforeCommit {
		_, err := blockTx.ExecContext(ctx, s.sql, s.args...)
		require.NoError(t, err)
	}
	require.NoError(t, blockTx.Commit())
	committed = true

	select {
	case err := <-raceResult:
		return err
	case <-ctx.Done():
		t.Fatalf("racing statement did not finish: %v", ctx.Err())
		return nil
	}
}
