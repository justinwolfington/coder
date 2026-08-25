package database_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/coder/coder/v2/coderd/database"
	"github.com/coder/coder/v2/coderd/database/dbgen"
	"github.com/coder/coder/v2/coderd/database/dbtestutil"
	"github.com/coder/coder/v2/testutil"
)

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

// runLockRace executes the blocking statements in one transaction, launches
// racing on a dedicated connection, deterministically waits for it to block
// on a row lock held by the blocking transaction, executes beforeCommit
// inside the blocking transaction, commits it, and returns the racing
// statement's error.
func runLockRace(ctx context.Context, t *testing.T, sqlDB *sql.DB, blocking []stmt, racing stmt, beforeCommit []stmt) error {
	t.Helper()

	blockTx, err := sqlDB.BeginTx(ctx, nil)
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

	raceResult := make(chan error, 1)
	go func() {
		_, err := raceConn.ExecContext(ctx, racing.sql, racing.args...)
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

// TestSoftDeleteGuardWinsConcurrentInsert verifies that all six soft-delete
// guard triggers serialize against a concurrent user soft-delete via the
// parent-row lock added in migration 000585: the insert blocks on the locked
// users row and, once the soft-delete commits, fails with the guard's
// constraint instead of resurrecting a row for the deleted user.
func TestSoftDeleteGuardWinsConcurrentInsert(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	// Shared parents for the FK-bearing tables.
	org := dbgen.Organization(t, db, database.Organization{})
	provider := dbgen.AIProvider(t, db, database.AIProvider{})

	testCases := []struct {
		name       string
		table      string
		constraint database.CheckConstraint
		insert     func(userID uuid.UUID) stmt
	}{
		{
			name:       "APIKey",
			table:      "api_keys",
			constraint: "api_key_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO api_keys (id, hashed_secret, user_id, last_used, expires_at, created_at, updated_at, login_type, scopes, allow_list)
					VALUES ($1, 'race-hash'::bytea, $2, now(), now() + interval '1 hour', now(), now(), 'password', '{}'::api_key_scope[], ARRAY['*'])
				`, []any{uuid.NewString(), userID}}
			},
		},
		{
			name:       "UserLink",
			table:      "user_links",
			constraint: "user_link_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO user_links (user_id, login_type, linked_id)
					VALUES ($1, 'github', 'race-link')
				`, []any{userID}}
			},
		},
		{
			name:       "UserSecret",
			table:      "user_secrets",
			constraint: "user_secret_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO user_secrets (id, user_id, name, description, value, env_name)
					VALUES ($1, $2, 'race-secret', '', 'value', 'RACE_SECRET')
				`, []any{uuid.New(), userID}}
			},
		},
		{
			name:       "UserSkill",
			table:      "user_skills",
			constraint: "user_skill_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO user_skills (id, user_id, name, description, content)
					VALUES ($1, $2, 'race-skill', '', 'content')
				`, []any{uuid.New(), userID}}
			},
		},
		{
			name:       "UserAIProviderKey",
			table:      "user_ai_provider_keys",
			constraint: "user_ai_provider_key_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO user_ai_provider_keys (id, user_id, ai_provider_id, api_key)
					VALUES ($1, $2, $3, 'race-key')
				`, []any{uuid.New(), userID, provider.ID}}
			},
		},
		{
			name:       "OrganizationMember",
			table:      "organization_members",
			constraint: "organization_member_user_deleted",
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO organization_members (user_id, organization_id, created_at, updated_at)
					VALUES ($1, $2, now(), now())
				`, []any{userID, org.ID}}
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx := testutil.Context(t, testutil.WaitLong)
			user := dbgen.User(t, db, database.User{})

			// Hold the same lock the guard trigger takes so the insert
			// blocks, then soft-delete before releasing it.
			err := runLockRace(ctx, t, sqlDB,
				[]stmt{{`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, []any{user.ID}}},
				tc.insert(user.ID),
				[]stmt{{`UPDATE users SET deleted = true WHERE id = $1`, []any{user.ID}}},
			)
			require.Error(t, err)
			require.True(t, database.IsCheckViolation(err, tc.constraint), "expected constraint %q, got: %v", tc.constraint, err)

			var remaining int
			//nolint:gosec // The table name comes from the test case definition.
			err = sqlDB.QueryRowContext(ctx,
				`SELECT count(*) FROM `+tc.table+` WHERE user_id = $1`, user.ID,
			).Scan(&remaining)
			require.NoError(t, err)
			require.Zero(t, remaining, "no rows may survive for the soft-deleted user")
		})
	}
}

// TestSoftDeleteGuardUpdatePathTakesNoUserLock pins the TG_OP gates: neither
// the soft-delete guards nor the user_secrets cap trigger take a users-row
// lock on the UPDATE path, so routine child-row updates proceed while the
// users row is locked. Without the gates this would block here and could
// deadlock in production against delete_deleted_user_resources.
func TestSoftDeleteGuardUpdatePathTakesNoUserLock(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	ctx := testutil.Context(t, testutil.WaitLong)
	user := dbgen.User(t, db, database.User{})

	_, err := sqlDB.ExecContext(ctx, `
		INSERT INTO user_skills (id, user_id, name, description, content)
		VALUES ($1, $2, 'gate-skill', '', 'content')
	`, uuid.New(), user.ID)
	require.NoError(t, err)
	_, err = sqlDB.ExecContext(ctx, `
		INSERT INTO user_links (user_id, login_type, linked_id)
		VALUES ($1, 'github', 'gate-link')
	`, user.ID)
	require.NoError(t, err)
	_, err = sqlDB.ExecContext(ctx, `
		INSERT INTO user_secrets (id, user_id, name, description, value, env_name)
		VALUES ($1, $2, 'gate-secret', '', 'value', 'GATE_SECRET')
	`, uuid.New(), user.ID)
	require.NoError(t, err)

	lockTx, err := sqlDB.BeginTx(ctx, nil)
	require.NoError(t, err)
	defer func() { _ = lockTx.Rollback() }()
	var lockedUserID uuid.UUID
	err = lockTx.QueryRowContext(ctx,
		`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, user.ID,
	).Scan(&lockedUserID)
	require.NoError(t, err)
	require.Equal(t, user.ID, lockedUserID)

	// All updates must complete while the users row is locked; blocking
	// here would mean a trigger locked the parent on the UPDATE path. The
	// lock_timeout bounds the wait so a blocked update fails the test
	// instead of waiting for the shared context deadline to roll back
	// lockTx and release the lock (which would let the update succeed and
	// mask a missing TG_OP gate).
	updateConn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = updateConn.Close() })
	_, err = updateConn.ExecContext(ctx, `SET lock_timeout = '5s'`)
	require.NoError(t, err)

	_, err = updateConn.ExecContext(ctx,
		`UPDATE user_skills SET description = 'edited' WHERE user_id = $1`, user.ID)
	require.NoError(t, err)
	_, err = updateConn.ExecContext(ctx,
		`UPDATE user_links SET linked_id = 'edited' WHERE user_id = $1`, user.ID)
	require.NoError(t, err)
	_, err = updateConn.ExecContext(ctx,
		`UPDATE user_secrets SET description = 'edited' WHERE user_id = $1`, user.ID)
	require.NoError(t, err)
}
