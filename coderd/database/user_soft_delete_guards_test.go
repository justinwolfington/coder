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

// TestSoftDeleteGuardWinsConcurrentInsert verifies that all seven soft-delete
// guard triggers serialize against a concurrent user soft-delete via the
// parent-row lock added in migration 000587: the insert blocks on the locked
// users row and, once the soft-delete commits, fails with the guard's
// constraint instead of resurrecting a row for the deleted user. Each
// subtest also pins its database.Check* constant against the live trigger by
// matching the raised constraint name.
func TestSoftDeleteGuardWinsConcurrentInsert(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	// Shared parents for the FK-bearing tables.
	org := dbgen.Organization(t, db, database.Organization{})
	provider := dbgen.AIProvider(t, db, database.AIProvider{})
	group := dbgen.Group(t, db, database.Group{OrganizationID: org.ID})

	testCases := []struct {
		name       string
		table      string
		constraint database.CheckConstraint
		// seed prepares rows the insert depends on (memberships etc.).
		seed   func(ctx context.Context, t *testing.T, userID uuid.UUID)
		insert func(userID uuid.UUID) stmt
	}{
		{
			name:       "APIKey",
			table:      "api_keys",
			constraint: database.CheckAPIKeyUserDeleted,
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
			constraint: database.CheckUserLinkUserDeleted,
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
			constraint: database.CheckUserSecretUserDeleted,
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
			constraint: database.CheckUserSkillUserDeleted,
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
			constraint: database.CheckUserAIProviderKeyUserDeleted,
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
			constraint: database.CheckOrganizationMemberUserDeleted,
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO organization_members (user_id, organization_id, created_at, updated_at)
					VALUES ($1, $2, now(), now())
				`, []any{userID, org.ID}}
			},
		},
		{
			name:       "UserAIBudgetOverride",
			table:      "user_ai_budget_overrides",
			constraint: database.CheckUserAIBudgetOverrideUserDeleted,
			// The membership trigger on this table fires before the guard
			// (name order) and rejects non-members outright, so the racing
			// user must be an org and group member for the insert to reach
			// the guard's users lock.
			seed: func(ctx context.Context, t *testing.T, userID uuid.UUID) {
				_, err := sqlDB.ExecContext(ctx, `
					INSERT INTO organization_members (user_id, organization_id, created_at, updated_at)
					VALUES ($1, $2, now(), now())
				`, userID, org.ID)
				require.NoError(t, err)
				_, err = sqlDB.ExecContext(ctx,
					`INSERT INTO group_members (user_id, group_id) VALUES ($1, $2)`,
					userID, group.ID)
				require.NoError(t, err)
			},
			insert: func(userID uuid.UUID) stmt {
				return stmt{`
					INSERT INTO user_ai_budget_overrides (user_id, group_id, spend_limit_micros)
					VALUES ($1, $2, 0)
				`, []any{userID, group.ID}}
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx := testutil.Context(t, testutil.WaitLong)
			user := dbgen.User(t, db, database.User{})
			if tc.seed != nil {
				tc.seed(ctx, t, user.ID)
			}

			// Hold the same lock the guard trigger takes so the insert
			// blocks, then soft-delete before releasing it.
			err := runLockRace(ctx, t, sqlDB, sql.LevelDefault,
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
	// here would mean a trigger locked the parent on the UPDATE path, so
	// the lock_timeout turns a missing TG_OP gate into a failure.
	updateConn := lockTimeoutConn(ctx, t, sqlDB, "5s")

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
		// Fetch the two triggers from the live catalog in firing (name)
		// order, so the assertion derives from the database rather than
		// comparing the test's own literals.
		rows, err := sqlDB.QueryContext(ctx, `
			SELECT tgname FROM pg_trigger
			WHERE tgrelid = $1::regclass AND NOT tgisinternal AND tgname IN ($2, $3)
			ORDER BY tgname
		`, tc.table, tc.guard, tc.capName)
		require.NoError(t, err)
		var firingOrder []string
		for rows.Next() {
			var name string
			require.NoError(t, rows.Scan(&name))
			firingOrder = append(firingOrder, name)
		}
		require.NoError(t, rows.Err())
		require.NoError(t, rows.Close())
		require.Equal(t, []string{tc.guard, tc.capName}, firingOrder,
			"%s: both triggers must exist and the guard must sort (and therefore fire) before the cap trigger", tc.table)
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
// Remove the users-lock SELECT at the top of the app transaction below (the
// statement mirroring AcquireUserSoftDeleteGuardLock) and the replay
// deadlocks: the soft-delete's cleanup waits on the child row while the app
// transaction waits on the users row (SQLSTATE 40P01).
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

	// The advisory-lock leg of the ordering contract: an update-then-insert
	// user_secrets writer holds the per-user advisory lock (from the
	// UPDATE-path cap trigger) with no users lock, so a concurrent insert
	// that holds the users lock and waits on the advisory lock would cycle
	// with it. Taking the users lock first (as the contract requires)
	// serializes the two: the concurrent insert queues behind the users
	// lock and both finish. No Go path does update-then-insert on
	// user_secrets today; this pins the contract the cap comments state.
	t.Run("SecretsUpdateThenInsert", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		secret := uuid.New()
		_, err := sqlDB.ExecContext(ctx, `
			INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
			VALUES ($1, $2, 'update-then-insert', '', 'value', '', '/tmp/update-then-insert')
		`, secret, user.ID)
		require.NoError(t, err)

		// The contract-following writer: users lock, then UPDATE (advisory
		// lock), then INSERT. The concurrent insert blocks on the users
		// lock instead of interleaving into the advisory cycle, and
		// succeeds once the writer commits.
		err = runLockRace(ctx, t, sqlDB, sql.LevelDefault,
			[]stmt{
				{`SELECT id FROM users WHERE id = $1 FOR NO KEY UPDATE`, []any{user.ID}},
				{`UPDATE user_secrets SET value = 'edited' WHERE id = $1`, []any{secret}},
			},
			stmt{`
				INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
				VALUES ($1, $2, 'concurrent-insert', '', 'value', '', '/tmp/concurrent-insert')
			`, []any{uuid.New(), user.ID}},
			[]stmt{
				{`
					INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
					VALUES ($1, $2, 'writer-insert', '', 'value', '', '/tmp/writer-insert')
				`, []any{uuid.New(), user.ID}},
			},
		)
		require.NoError(t, err, "with the users lock taken first, neither side may deadlock")
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

// TestSoftDeleteGuardRejectsUpdatesForDeletedUser pins the guard's UPDATE
// branch (the unlocked deleted-check) on the three upsert tables: a child
// row that survived cleanup must not keep being updated, or an orphaned
// user_links row could keep having its OAuth tokens refreshed.
func TestSoftDeleteGuardRejectsUpdatesForDeletedUser(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	testCases := []struct {
		name       string
		constraint database.CheckConstraint
		seed       func(ctx context.Context, t *testing.T, userID uuid.UUID)
		update     stmt
	}{
		{
			name:       "UserLink",
			constraint: database.CheckUserLinkUserDeleted,
			seed: func(ctx context.Context, t *testing.T, userID uuid.UUID) {
				_, err := sqlDB.ExecContext(ctx, `
					INSERT INTO user_links (user_id, login_type, linked_id)
					VALUES ($1, 'oidc', 'update-branch-link')
				`, userID)
				require.NoError(t, err)
			},
			update: stmt{`UPDATE user_links SET oauth_access_token = 'refreshed' WHERE user_id = $1`, nil},
		},
		{
			name:       "UserSecret",
			constraint: database.CheckUserSecretUserDeleted,
			seed: func(ctx context.Context, t *testing.T, userID uuid.UUID) {
				_, err := sqlDB.ExecContext(ctx, `
					INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
					VALUES ($1, $2, 'update-branch-secret', '', 'value', '', '/tmp/update-branch-secret')
				`, uuid.New(), userID)
				require.NoError(t, err)
			},
			update: stmt{`UPDATE user_secrets SET value = 'edited' WHERE user_id = $1`, nil},
		},
		{
			name:       "UserSkill",
			constraint: database.CheckUserSkillUserDeleted,
			seed: func(ctx context.Context, t *testing.T, userID uuid.UUID) {
				_, err := sqlDB.ExecContext(ctx, `
					INSERT INTO user_skills (id, user_id, name, description, content)
					VALUES ($1, $2, 'update-branch-skill', '', 'content')
				`, uuid.New(), userID)
				require.NoError(t, err)
			},
			update: stmt{`UPDATE user_skills SET description = 'edited' WHERE user_id = $1`, nil},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx := testutil.Context(t, testutil.WaitLong)
			user := dbgen.User(t, db, database.User{})
			tc.seed(ctx, t, user.ID)

			dbtestutil.SoftDeleteUserKeepingRows(ctx, t, sqlDB, user.ID)

			_, err := sqlDB.ExecContext(ctx, tc.update.sql, user.ID)
			require.Error(t, err, "updating a surviving child row of a deleted user must fail")
			require.True(t, database.IsCheckViolation(err, tc.constraint),
				"expected constraint %q, got: %v", tc.constraint, err)
		})
	}
}

// TestUserCapsRequireReadCommitted pins require_read_committed on both cap
// triggers: the caps count committed sibling rows, so any isolation level
// whose snapshot can survive a lock wait is rejected, while READ UNCOMMITTED
// (which PostgreSQL executes with READ COMMITTED semantics) is accepted.
func TestUserCapsRequireReadCommitted(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)

	insertSecret := func(userID uuid.UUID) stmt {
		return stmt{`
			INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
			VALUES ($1, $2, 'isolation-secret', '', 'value', '', '/tmp/isolation-secret')
		`, []any{uuid.New(), userID}}
	}
	insertSkill := func(userID uuid.UUID) stmt {
		return stmt{`
			INSERT INTO user_skills (id, user_id, name, description, content)
			VALUES ($1, $2, 'isolation-skill', '', 'content')
		`, []any{uuid.New(), userID}}
	}

	t.Run("Rejected", func(t *testing.T) {
		t.Parallel()
		for _, level := range []sql.IsolationLevel{sql.LevelRepeatableRead, sql.LevelSerializable} {
			for _, tc := range []struct {
				name       string
				constraint database.CheckConstraint
				insert     func(userID uuid.UUID) stmt
			}{
				{"UserSecret", database.CheckUserSecretsCapIsolation, insertSecret},
				{"UserSkill", database.CheckUserSkillsCapIsolation, insertSkill},
			} {
				t.Run(tc.name+"/"+level.String(), func(t *testing.T) {
					t.Parallel()
					ctx := testutil.Context(t, testutil.WaitLong)
					user := dbgen.User(t, db, database.User{})

					tx, err := sqlDB.BeginTx(ctx, &sql.TxOptions{Isolation: level})
					require.NoError(t, err)
					defer tx.Rollback() //nolint:errcheck // rollback after expected failure
					ins := tc.insert(user.ID)
					_, err = tx.ExecContext(ctx, ins.sql, ins.args...)
					require.Error(t, err)
					require.True(t, database.IsCheckViolation(err, tc.constraint),
						"expected constraint %q, got: %v", tc.constraint, err)
				})
			}
		}
	})

	// A same-owner user_secrets update under REPEATABLE READ is exempt from
	// the isolation gate: dbcrypt rotation rewrites values under RR and its
	// serialization failure on concurrent modification is load-bearing.
	t.Run("SameOwnerSecretUpdateAllowedAtRepeatableRead", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})
		secret := uuid.New()
		_, err := sqlDB.ExecContext(ctx, `
			INSERT INTO user_secrets (id, user_id, name, description, value, env_name, file_path)
			VALUES ($1, $2, 'rotate-secret', '', 'value', '', '/tmp/rotate-secret')
		`, secret, user.ID)
		require.NoError(t, err)

		tx, err := sqlDB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead})
		require.NoError(t, err)
		defer tx.Rollback() //nolint:errcheck // no-op after commit
		_, err = tx.ExecContext(ctx,
			`UPDATE user_secrets SET value = 'rotated' WHERE id = $1`, secret)
		require.NoError(t, err, "a same-owner update must not trip the isolation gate")
		require.NoError(t, tx.Commit())
	})

	// READ UNCOMMITTED is accepted, and the cap still holds under it: two
	// racing inserts at the cap serialize on the advisory lock, and the
	// second recounts the first's committed row because PostgreSQL runs
	// READ UNCOMMITTED with READ COMMITTED semantics.
	t.Run("ReadUncommittedCapHolds", func(t *testing.T) {
		t.Parallel()
		ctx := testutil.Context(t, testutil.WaitLong)
		user := dbgen.User(t, db, database.User{})

		// Seed to one under the cap of 100 so exactly one racer fits.
		_, err := sqlDB.ExecContext(ctx, `
			INSERT INTO user_skills (id, user_id, name, description, content)
			SELECT gen_random_uuid(), $1, 'seed-skill-' || g, '', 'content'
			FROM generate_series(1, 99) AS g
		`, user.ID)
		require.NoError(t, err)

		err = runLockRace(ctx, t, sqlDB, sql.LevelReadUncommitted,
			[]stmt{insertSkill(user.ID)},
			insertSkill(user.ID),
			nil,
		)
		require.Error(t, err, "the racing insert must recount and fail the cap")
		require.True(t, database.IsCheckViolation(err, "user_skills_per_user_limit"),
			"expected the skill cap violation, got: %v", err)

		var count int
		require.NoError(t, sqlDB.QueryRowContext(ctx,
			`SELECT count(*) FROM user_skills WHERE user_id = $1`, user.ID,
		).Scan(&count))
		require.Equal(t, 100, count, "the cap must hold at exactly 100")
	})
}

// TestUserSkillsCapOwnerReassignment pins the UPDATE leg of the skills cap
// trigger: a same-owner update at the cap succeeds (the count cannot
// change), while reassigning a row onto an owner already at the cap fails,
// closing the UPDATE ... SET user_id bypass.
func TestUserSkillsCapOwnerReassignment(t *testing.T) {
	t.Parallel()
	if testing.Short() {
		t.SkipNow()
	}

	db, _, sqlDB := dbtestutil.NewDBWithSQLDB(t)
	ctx := testutil.Context(t, testutil.WaitLong)
	fullUser := dbgen.User(t, db, database.User{})
	otherUser := dbgen.User(t, db, database.User{})

	// Fill fullUser to the cap of 100.
	_, err := sqlDB.ExecContext(ctx, `
		INSERT INTO user_skills (id, user_id, name, description, content)
		SELECT gen_random_uuid(), $1, 'cap-skill-' || g, '', 'content'
		FROM generate_series(1, 100) AS g
	`, fullUser.ID)
	require.NoError(t, err)

	// A same-owner update at the cap must succeed: the trigger returns
	// early because the count cannot change.
	_, err = sqlDB.ExecContext(ctx, `
		UPDATE user_skills SET description = 'edited'
		WHERE user_id = $1 AND name = 'cap-skill-1'
	`, fullUser.ID)
	require.NoError(t, err, "a same-owner update at the cap must not trip the cap")

	// Reassigning another user's row onto the full owner must fail.
	movingSkill := uuid.New()
	_, err = sqlDB.ExecContext(ctx, `
		INSERT INTO user_skills (id, user_id, name, description, content)
		VALUES ($1, $2, 'moving-skill', '', 'content')
	`, movingSkill, otherUser.ID)
	require.NoError(t, err)
	_, err = sqlDB.ExecContext(ctx,
		`UPDATE user_skills SET user_id = $1 WHERE id = $2`, fullUser.ID, movingSkill)
	require.Error(t, err, "reassigning onto a full owner must fail the cap")
	require.True(t, database.IsCheckViolation(err, "user_skills_per_user_limit"),
		"expected the skill cap violation, got: %v", err)

	// Reassigning onto an owner with room succeeds: the moving row still
	// belongs to the old owner while counting, so the count is exact.
	roomUser := dbgen.User(t, db, database.User{})
	_, err = sqlDB.ExecContext(ctx,
		`UPDATE user_skills SET user_id = $1 WHERE id = $2`, roomUser.ID, movingSkill)
	require.NoError(t, err, "reassigning onto an owner with room must succeed")
}
