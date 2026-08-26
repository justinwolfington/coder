package database_test

import (
	"context"
	"database/sql"
	"strings"
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
// parent-row lock added in migration 000587: the insert blocks on the locked
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
	// Reset before the connection returns to the pool; database/sql does
	// not reset session state. Cleanups run LIFO, so this runs before Close.
	t.Cleanup(func() { _, _ = updateConn.ExecContext(context.Background(), `RESET lock_timeout`) })

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

// TestSoftDeleteGuardTriggerOrder pins the trigger firing order the advisory
// cap locks depend on: BEFORE triggers fire in name order, and the soft-delete
// guards (users lock) must fire before the zz_-prefixed cap triggers
// (advisory lock). A transaction that held the advisory lock while waiting on
// the users lock could cycle with an UPDATE-path advisory waiter and the
// soft-delete cleanup.
func TestSoftDeleteGuardTriggerOrder(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	_, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	ctx := testutil.Context(t, testutil.WaitShort)

	for _, tc := range []struct {
		table   string
		guard   string
		capName string
	}{
		{"user_secrets", "trigger_upsert_user_secrets", "trigger_zz_user_secrets_per_user_limits"},
		{"user_skills", "trigger_upsert_user_skills", "trigger_zz_user_skills_per_user_limit"},
	} {
		var present int
		err := sqlDB.QueryRowContext(ctx, `
			SELECT count(*) FROM pg_trigger
			WHERE tgrelid = $1::regclass AND NOT tgisinternal AND tgname IN ($2, $3)
		`, tc.table, tc.guard, tc.capName).Scan(&present)
		require.NoError(t, err)
		require.Equal(t, 2, present, "%s: both the guard and the cap trigger must exist", tc.table)
		require.Less(t, tc.guard, tc.capName,
			"%s: the guard trigger must sort (and therefore fire) before the cap trigger", tc.table)
	}
}

// runGuardedWriteRace deterministically replays a delete-or-update-then-insert
// transaction against a concurrent user soft-delete:
//
//  1. An outside transaction locks the child row the app transaction will
//     touch, so the app transaction blocks mid-flight while already holding
//     the users lock it took first (mirroring AcquireUserSoftDeleteGuardLock).
//  2. The soft-delete starts and queues behind the app transaction's users
//     lock instead of interleaving into a lock-order inversion.
//  3. The outside lock is released; the app transaction finishes cleanly and
//     the soft-delete then runs its cleanup.
//
// Remove the AcquireUserSoftDeleteGuardLock call from the mirrored Go path
// (drop the acquireFirst statement here) and the replay deadlocks: the
// soft-delete's cleanup waits on the child row while the app transaction
// waits on the users row (SQLSTATE 40P01).
func runGuardedWriteRace(ctx context.Context, t *testing.T, sqlDB *sql.DB, userID uuid.UUID, childLock stmt, appStmts []stmt) {
	t.Helper()

	outsideTx, err := sqlDB.BeginTx(ctx, nil)
	require.NoError(t, err)
	released := false
	t.Cleanup(func() {
		if !released {
			_ = outsideTx.Rollback()
		}
	})
	_, err = outsideTx.ExecContext(ctx, childLock.sql, childLock.args...)
	require.NoError(t, err)

	appConn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = appConn.Close() })
	var appPID int
	require.NoError(t, appConn.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&appPID))
	appResult := make(chan error, 1)
	go func() {
		appResult <- func() error {
			tx, err := appConn.BeginTx(ctx, nil)
			if err != nil {
				return err
			}
			defer func() { _ = tx.Rollback() }()
			var lockedID uuid.UUID
			err = tx.QueryRowContext(ctx,
				`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, userID,
			).Scan(&lockedID)
			if err != nil {
				return err
			}
			for _, s := range appStmts {
				if _, err := tx.ExecContext(ctx, s.sql, s.args...); err != nil {
					return err
				}
			}
			return tx.Commit()
		}()
	}()
	waitForBackendBlocked(ctx, t, sqlDB, appPID)

	deleteConn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = deleteConn.Close() })
	var deletePID int
	require.NoError(t, deleteConn.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&deletePID))
	deleteResult := make(chan error, 1)
	go func() {
		_, err := deleteConn.ExecContext(ctx, `UPDATE users SET deleted = true WHERE id = $1`, userID)
		deleteResult <- err
	}()
	waitForBackendBlocked(ctx, t, sqlDB, deletePID)

	require.NoError(t, outsideTx.Rollback())
	released = true

	select {
	case err := <-appResult:
		require.NoError(t, err, "the app transaction must finish without deadlocking")
	case <-ctx.Done():
		t.Fatalf("app transaction did not finish: %v", ctx.Err())
	}
	select {
	case err := <-deleteResult:
		require.NoError(t, err, "the soft-delete must finish without deadlocking")
	case <-ctx.Done():
		t.Fatalf("soft-delete did not finish: %v", ctx.Err())
	}
}

// TestSoftDeleteGuardLockOrderPaths is the per-path deadlock-regression suite
// for the ordering contract documented on AcquireUserSoftDeleteGuardLock:
// each subtest mirrors the exact statement order of one Go transaction that
// locks a guarded child row and later inserts one, and fails with a deadlock
// if the users lock is not taken first.
func TestSoftDeleteGuardLockOrderPaths(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	org := dbgen.Organization(t, db, database.Organization{})

	insertAPIKey := func(userID uuid.UUID) stmt {
		return stmt{`
			INSERT INTO api_keys (id, hashed_secret, user_id, last_used, expires_at, created_at, updated_at, login_type, scopes, allow_list)
			VALUES ($1, 'lock-order-hash'::bytea, $2, now(), now() + interval '1 hour', now(), now(), 'password', '{}'::api_key_scope[], ARRAY['*'])
		`, []any{uuid.NewString(), userID}}
	}

	// Mirrors coderd/oauth2provider/tokens.go: both token grants delete the
	// previous api_keys row and insert its replacement.
	t.Run("OAuth2TokenReplacement", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		prevKey, _ := dbgen.APIKey(t, db, database.APIKey{UserID: user.ID})

		runGuardedWriteRace(ctx, t, sqlDB, user.ID,
			stmt{`SELECT 1 FROM api_keys WHERE id = $1 FOR UPDATE`, []any{prevKey.ID}},
			[]stmt{
				{`DELETE FROM api_keys WHERE id = $1`, []any{prevKey.ID}},
				insertAPIKey(user.ID),
			},
		)
	})

	// Mirrors coderd/provisionerdserver regenerateSessionToken: delete the
	// workspace session token by name, insert the replacement.
	t.Run("RegenerateSessionToken", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		sessionKey, _ := dbgen.APIKey(t, db, database.APIKey{UserID: user.ID, TokenName: "session-token-lock-order"})

		runGuardedWriteRace(ctx, t, sqlDB, user.ID,
			stmt{`SELECT 1 FROM api_keys WHERE id = $1 FOR UPDATE`, []any{sessionKey.ID}},
			[]stmt{
				{`DELETE FROM api_keys WHERE user_id = $1 AND token_name = $2`, []any{user.ID, "session-token-lock-order"}},
				insertAPIKey(user.ID),
			},
		)
	})

	// Mirrors coderd/userauth.go oauthLogin: update the user_links row for
	// the fresh OAuth tokens, then insert organization_members via org sync.
	t.Run("OAuthLoginOrgSync", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		_, err := sqlDB.ExecContext(ctx, `
			INSERT INTO user_links (user_id, login_type, linked_id)
			VALUES ($1, 'oidc', 'lock-order-link')
		`, user.ID)
		require.NoError(t, err)

		runGuardedWriteRace(ctx, t, sqlDB, user.ID,
			stmt{`SELECT 1 FROM user_links WHERE user_id = $1 AND login_type = 'oidc' FOR UPDATE`, []any{user.ID}},
			[]stmt{
				{`UPDATE user_links SET oauth_access_token = 'refreshed' WHERE user_id = $1 AND login_type = 'oidc'`, []any{user.ID}},
				{`INSERT INTO organization_members (user_id, organization_id, created_at, updated_at) VALUES ($1, $2, now(), now())`, []any{user.ID, org.ID}},
			},
		)
	})
}

// TestUserSecretsCapConcurrentUpdates verifies the per-user advisory lock
// serializes concurrent user_secrets updates so the byte caps hold: two
// transactions growing different rows of the same user must not both pass
// the pre-statement aggregate check.
func TestUserSecretsCapConcurrentUpdates(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	ctx := testutil.Context(t, testutil.WaitLong)
	user := dbgen.User(t, db, database.User{})

	// file_path targets keep the values out of the (much smaller)
	// env-injected byte cap so the test exercises the total-bytes cap.
	secretA, secretB := uuid.New(), uuid.New()
	for i, id := range []uuid.UUID{secretA, secretB} {
		_, err := sqlDB.ExecContext(ctx, `
			INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
			VALUES ($1, $2, 'cap-secret-'||$3::text, '', 'small', '', '/tmp/cap-secret-'||$3::text)
		`, id, user.ID, i)
		require.NoError(t, err)
	}

	// 150000 bytes each: either alone fits the 204800-byte cap, both
	// together exceed it.
	bigValue := strings.Repeat("x", 150000)

	firstTx, err := sqlDB.BeginTx(ctx, nil)
	require.NoError(t, err)
	committed := false
	t.Cleanup(func() {
		if !committed {
			_ = firstTx.Rollback()
		}
	})
	_, err = firstTx.ExecContext(ctx,
		`UPDATE user_secrets SET value = $1 WHERE id = $2`, bigValue, secretA)
	require.NoError(t, err)

	// The second update must block on the advisory lock held by firstTx,
	// then recount against firstTx's committed state and fail the cap.
	secondConn, err := sqlDB.Conn(ctx)
	require.NoError(t, err)
	t.Cleanup(func() { _ = secondConn.Close() })
	var secondPID int
	require.NoError(t, secondConn.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&secondPID))
	secondResult := make(chan error, 1)
	go func() {
		_, err := secondConn.ExecContext(ctx,
			`UPDATE user_secrets SET value = $1 WHERE id = $2`, bigValue, secretB)
		secondResult <- err
	}()
	waitForBackendBlocked(ctx, t, sqlDB, secondPID)

	require.NoError(t, firstTx.Commit())
	committed = true

	select {
	case err := <-secondResult:
		require.Error(t, err, "the second update must not bypass the byte cap")
		require.True(t, database.IsCheckViolation(err, "user_secrets_per_user_total_bytes_limit"),
			"expected the total-bytes cap violation, got: %v", err)
	case <-ctx.Done():
		t.Fatalf("second update did not finish: %v", ctx.Err())
	}

	var totalBytes int64
	err = sqlDB.QueryRowContext(ctx,
		`SELECT coalesce(sum(octet_length(value)), 0) FROM user_secrets WHERE user_id = $1`, user.ID,
	).Scan(&totalBytes)
	require.NoError(t, err)
	require.LessOrEqual(t, totalBytes, int64(204800), "the committed total must respect the cap")
}

// TestDeletedUserHasNoAuthorizationRoles pins the read-side half of the
// soft-delete guards: GetAuthorizationUserRoles refuses deleted users, so a
// child row that survived or bypassed delete_deleted_user_resources (an
// orphaned api_keys row, a restored backup, a manual insert) cannot
// authenticate regardless of its source.
func TestDeletedUserHasNoAuthorizationRoles(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	ctx := testutil.Context(t, testutil.WaitLong)
	user := dbgen.User(t, db, database.User{})
	orphanKey, _ := dbgen.APIKey(t, db, database.APIKey{UserID: user.ID})

	// Soft-delete while suppressing the cleanup trigger, reconstructing the
	// orphaned-credential state the write-side guards exist to prevent. One
	// transaction: transactional DDL keeps the disabled trigger invisible
	// to other sessions and re-enables it even on failure via rollback.
	tx, err := sqlDB.BeginTx(ctx, nil)
	require.NoError(t, err)
	committed := false
	t.Cleanup(func() {
		if !committed {
			_ = tx.Rollback()
		}
	})
	_, err = tx.ExecContext(ctx, `ALTER TABLE users DISABLE TRIGGER trigger_update_users`)
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, `UPDATE users SET deleted = true WHERE id = $1`, user.ID)
	require.NoError(t, err)
	_, err = tx.ExecContext(ctx, `ALTER TABLE users ENABLE TRIGGER trigger_update_users`)
	require.NoError(t, err)
	require.NoError(t, tx.Commit())
	committed = true

	var keyCount int
	err = sqlDB.QueryRowContext(ctx,
		`SELECT count(*) FROM api_keys WHERE id = $1`, orphanKey.ID,
	).Scan(&keyCount)
	require.NoError(t, err)
	require.Equal(t, 1, keyCount, "the orphaned key must survive for this test to mean anything")

	_, err = db.GetAuthorizationUserRoles(ctx, user.ID)
	require.ErrorIs(t, err, sql.ErrNoRows, "a deleted user must have no authorization roles")
}
