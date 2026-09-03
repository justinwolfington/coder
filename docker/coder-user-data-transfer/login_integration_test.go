package main

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestLoginMigrationIntegration(t *testing.T) {
	db, ctx := openIntegrationDatabase(t)

	t.Run("changes login while preserving user data", func(t *testing.T) {
		userID := uuid.New()
		targetEmail := "login-" + userID.String() + "@abridge.com"
		seedLoginMigrationUser(t, ctx, db, userID)

		plan, err := CreateLoginMigrationPlan(ctx, db, userID, targetEmail)
		if err != nil {
			t.Fatalf("CreateLoginMigrationPlan() error: %v", err)
		}
		if len(plan.Conflicts) != 0 {
			t.Fatalf("CreateLoginMigrationPlan() conflicts = %v, want none", plan.Conflicts)
		}
		assertLoginRetainedCount(t, plan, "workspaces", 1)
		assertLoginRetainedCount(t, plan, "api_keys", 1)
		assertLoginRetainedCount(t, plan, "github_identity_links", 1)
		assertLoginRetainedCount(t, plan, "oidc_identity_links", 0)

		_, err = ApplyLoginMigration(ctx, db, userID, targetEmail, strings.Repeat("0", 64))
		if err == nil || err.Error() != "plan-sha256 does not match the current database state" {
			t.Fatalf("ApplyLoginMigration() stale plan error = %v", err)
		}
		assertTrue(t, ctx, db, "login unchanged after rejected apply", `
			SELECT login_type = 'github' AND email LIKE '%@example.invalid'
			FROM users WHERE id = $1
		`, userID)
		mustExec(t, ctx, db, "insert concurrent retained API key", `
			INSERT INTO api_keys (
				id, hashed_secret, user_id, last_used, expires_at, created_at,
				updated_at, login_type, scopes, allow_list
			) VALUES (
				$1, decode('04', 'hex'), $2, now(), now() + interval '1 day',
				now(), now(), 'github', ARRAY['coder:all']::api_key_scope[], ARRAY['*']
			)
		`, "concurrent-"+userID.String(), userID)

		applied, err := ApplyLoginMigration(ctx, db, userID, targetEmail, plan.PlanSHA256)
		if err != nil {
			t.Fatalf("ApplyLoginMigration() error: %v", err)
		}
		if !applied.Applied || applied.PlanSHA256 != plan.PlanSHA256 {
			t.Fatal("ApplyLoginMigration() did not report the approved plan")
		}

		assertTrue(t, ctx, db, "user login migrated", `
			SELECT login_type = 'oidc' AND email = $2 AND octet_length(hashed_password) = 0
			FROM users WHERE id = $1
		`, userID, targetEmail)
		assertCount(t, ctx, db, "github identity retained", 1, `
			SELECT count(*) FROM user_links
			WHERE user_id = $1 AND login_type = 'github' AND linked_id <> ''
		`, userID)
		assertCount(t, ctx, db, "oidc identity awaiting first login", 0, `
			SELECT count(*) FROM user_links WHERE user_id = $1 AND login_type = 'oidc'
		`, userID)
		assertCount(t, ctx, db, "workspace retained", 1, `
			SELECT count(*) FROM workspaces WHERE owner_id = $1
		`, userID)
		assertCount(t, ctx, db, "API keys retained", 2, `
			SELECT count(*) FROM api_keys WHERE user_id = $1
		`, userID)
		assertCount(t, ctx, db, "external auth retained", 1, `
			SELECT count(*) FROM external_auth_links WHERE user_id = $1
		`, userID)
	})

	t.Run("rejects an email owned by another user", func(t *testing.T) {
		userID := uuid.New()
		targetID := uuid.New()
		targetEmail := "collision-" + targetID.String() + "@abridge.com"
		seedLoginMigrationUser(t, ctx, db, userID)
		seedOIDCUser(t, ctx, db, targetID, targetEmail)

		plan, err := CreateLoginMigrationPlan(ctx, db, userID, targetEmail)
		if err != nil {
			t.Fatalf("CreateLoginMigrationPlan() error: %v", err)
		}
		if len(plan.Conflicts) != 1 || plan.Conflicts[0].Kind != "target_email_in_use" {
			t.Fatalf("CreateLoginMigrationPlan() conflicts = %v", plan.Conflicts)
		}

		_, err = ApplyLoginMigration(ctx, db, userID, targetEmail, plan.PlanSHA256)
		if err == nil || err.Error() != "login migration plan contains conflicts" {
			t.Fatalf("ApplyLoginMigration() error = %v, want conflict refusal", err)
		}
		assertTrue(t, ctx, db, "login unchanged after conflict", `
			SELECT login_type = 'github' AND email LIKE '%@example.invalid'
			FROM users WHERE id = $1
		`, userID)
	})
}

func seedLoginMigrationUser(t *testing.T, ctx context.Context, db *sql.DB, userID uuid.UUID) {
	t.Helper()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin login migration fixture: %v", err)
	}
	defer tx.Rollback()
	mustExec(t, ctx, tx, "disable login migration fixture triggers", `SET LOCAL session_replication_role = replica`)
	mustExec(t, ctx, tx, "insert login migration user", `
		INSERT INTO users (
			id, email, username, hashed_password, created_at, updated_at,
			status, rbac_roles, login_type
		) VALUES (
			$1, $2, $3, decode('', 'hex'), now(), now(),
			'active', '{}', 'github'
		)
	`, userID, "github-"+userID.String()+"@example.invalid", "github-"+userID.String())
	mustExec(t, ctx, tx, "insert github identity link", `
		INSERT INTO user_links (user_id, login_type, linked_id)
		VALUES ($1, 'github', $2)
	`, userID, "github-identity-"+userID.String())
	mustExec(t, ctx, tx, "insert retained workspace", `
		INSERT INTO workspaces (
			id, created_at, updated_at, owner_id, organization_id,
			template_id, name
		) VALUES ($1, now(), now(), $2, $3, $4, $5)
	`, uuid.New(), userID, uuid.New(), uuid.New(), "login-"+userID.String())
	mustExec(t, ctx, tx, "insert retained external auth", `
		INSERT INTO external_auth_links (
			provider_id, user_id, created_at, updated_at, oauth_access_token,
			oauth_refresh_token, oauth_expiry
		) VALUES ('github', $1, now(), now(), 'access', 'refresh', now())
	`, userID)
	seedRetainedAuthentication(t, ctx, tx, userID, "login-"+userID.String(), "github", "03")
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit login migration fixture: %v", err)
	}
}

func seedOIDCUser(t *testing.T, ctx context.Context, db *sql.DB, userID uuid.UUID, email string) {
	t.Helper()

	mustExec(t, ctx, db, "insert OIDC target user", `
		INSERT INTO users (
			id, email, username, hashed_password, created_at, updated_at,
			status, rbac_roles, login_type
		) VALUES (
			$1, $2, $3, decode('', 'hex'), now(), now(),
			'active', '{}', 'oidc'
		)
	`, userID, email, "oidc-"+userID.String())
}

func assertLoginRetainedCount(t *testing.T, plan LoginMigrationPlan, resource string, want int64) {
	t.Helper()
	for _, count := range plan.Retained {
		if count.Resource == resource {
			if count.Count != want {
				t.Fatalf("login plan retained %s count = %d, want %d", resource, count.Count, want)
			}
			return
		}
	}
	t.Fatalf("login plan does not contain retained %s", resource)
}
