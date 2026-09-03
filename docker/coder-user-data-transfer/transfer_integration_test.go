package main

import (
	"context"
	"database/sql"
	"net"
	"net/url"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lib/pq"
)

const integrationDatabaseEnv = "CODER_TRANSFER_TEST_DATABASE_URL"

type fixtureIDs struct {
	source          uuid.UUID
	target          uuid.UUID
	organization    uuid.UUID
	group           uuid.UUID
	template        uuid.UUID
	templateVersion uuid.UUID
	workspace       uuid.UUID
	task            uuid.UUID
	chat            uuid.UUID
	chatFile        uuid.UUID
	fileOne         uuid.UUID
	fileTwo         uuid.UUID
	modelConfig     uuid.UUID
	mcpConfig       uuid.UUID
	aiProviderOne   uuid.UUID
	aiProviderTwo   uuid.UUID
	notification    uuid.UUID
}

func newFixtureIDs() fixtureIDs {
	return fixtureIDs{
		source:          uuid.New(),
		target:          uuid.New(),
		organization:    uuid.New(),
		group:           uuid.New(),
		template:        uuid.New(),
		templateVersion: uuid.New(),
		workspace:       uuid.New(),
		task:            uuid.New(),
		chat:            uuid.New(),
		chatFile:        uuid.New(),
		fileOne:         uuid.New(),
		fileTwo:         uuid.New(),
		modelConfig:     uuid.New(),
		mcpConfig:       uuid.New(),
		aiProviderOne:   uuid.New(),
		aiProviderTwo:   uuid.New(),
		notification:    uuid.New(),
	}
}

func TestTransferIntegration(t *testing.T) {
	db, ctx := openIntegrationDatabase(t)

	t.Run("classifies every user reference", func(t *testing.T) {
		assertUserReferenceInventory(t, ctx, db)
	})

	t.Run("moves data and preserves authentication", func(t *testing.T) {
		ids := newFixtureIDs()
		seedCompleteFixture(t, ctx, db, ids)

		plan, err := CreatePlan(ctx, db, ids.source, ids.target)
		if err != nil {
			t.Fatalf("CreatePlan() error: %v", err)
		}
		if len(plan.Conflicts) != 0 {
			t.Fatalf("CreatePlan() conflicts = %v, want none", plan.Conflicts)
		}
		assertPlannedCounts(t, plan, "workspaces", 1, 0)
		assertPlannedCounts(t, plan, "chat_messages", 1, 1)
		assertPlannedCounts(t, plan, "files", 1, 1)
		assertPlannedCounts(t, plan, "user_configs", 2, 2)
		assertPlannedCounts(t, plan, "ai_seat_state", 1, 1)
		assertRetainedCounts(t, plan, "chat_model_config_attribution", 1, 1)
		assertRetainedCounts(t, plan, "mcp_server_config_attribution", 1, 1)

		applied, err := ApplyTransfer(ctx, db, ids.source, ids.target, plan.PlanSHA256)
		if err != nil {
			t.Fatalf("ApplyTransfer() error: %v", err)
		}
		if !applied.Applied {
			t.Fatal("ApplyTransfer() did not report an applied plan")
		}
		if applied.PlanSHA256 != plan.PlanSHA256 {
			t.Fatal("ApplyTransfer() changed the approved plan digest")
		}

		assertSuccessfulTransfer(t, ctx, db, ids, 0, 1)
	})

	t.Run("retains colliding external auth links", func(t *testing.T) {
		ids := newFixtureIDs()
		seedCompleteFixture(t, ctx, db, ids)
		mustExec(t, ctx, db, "insert target external auth link", `
			INSERT INTO external_auth_links (
				provider_id, user_id, created_at, updated_at, oauth_access_token,
				oauth_refresh_token, oauth_expiry
			) VALUES ('github', $1, now(), now(), 'target-access', 'target-refresh', now())
		`, ids.target)

		plan, err := CreatePlan(ctx, db, ids.source, ids.target)
		if err != nil {
			t.Fatalf("CreatePlan() error: %v", err)
		}
		if len(plan.Conflicts) != 0 {
			t.Fatalf("CreatePlan() conflicts = %v, want none", plan.Conflicts)
		}
		assertSourceRetainedCount(t, plan, "external_auth_links", 1)

		applied, err := ApplyTransfer(ctx, db, ids.source, ids.target, plan.PlanSHA256)
		if err != nil {
			t.Fatalf("ApplyTransfer() error: %v", err)
		}
		if !applied.Applied {
			t.Fatal("ApplyTransfer() did not report an applied plan")
		}

		assertSuccessfulTransfer(t, ctx, db, ids, 1, 1)
		assertTrue(t, ctx, db, "source external auth credential retained", `
			SELECT oauth_access_token = $2 AND oauth_refresh_token = $3
			FROM external_auth_links WHERE user_id = $1 AND provider_id = 'github'
		`, ids.source, "access", "refresh")
		assertTrue(t, ctx, db, "target external auth credential retained", `
			SELECT oauth_access_token = $2 AND oauth_refresh_token = $3
			FROM external_auth_links WHERE user_id = $1 AND provider_id = 'github'
		`, ids.target, "target-access", "target-refresh")
	})

	t.Run("rejects conflicts without changes", func(t *testing.T) {
		ids := newFixtureIDs()
		seedWorkspaceConflictFixture(t, ctx, db, ids)

		plan, err := CreatePlan(ctx, db, ids.source, ids.target)
		if err != nil {
			t.Fatalf("CreatePlan() error: %v", err)
		}
		if len(plan.Conflicts) != 1 || plan.Conflicts[0].Kind != "active_workspace_name" {
			t.Fatalf("CreatePlan() conflicts = %v, want active_workspace_name", plan.Conflicts)
		}

		_, err = ApplyTransfer(ctx, db, ids.source, ids.target, plan.PlanSHA256)
		if err == nil || err.Error() != "transfer plan contains conflicts" {
			t.Fatalf("ApplyTransfer() error = %v, want conflict refusal", err)
		}
		assertCount(t, ctx, db, "source conflict workspace", 1, `
			SELECT count(*) FROM workspaces WHERE owner_id = $1
		`, ids.source)
		assertCount(t, ctx, db, "target conflict workspace", 1, `
			SELECT count(*) FROM workspaces WHERE owner_id = $1
		`, ids.target)
	})

	t.Run("rolls back a partial transfer", func(t *testing.T) {
		ids := newFixtureIDs()
		seedRollbackFixture(t, ctx, db, ids)

		plan, err := CreatePlan(ctx, db, ids.source, ids.target)
		if err != nil {
			t.Fatalf("CreatePlan() error: %v", err)
		}
		mustExec(t, ctx, db, "create failure function", `
			CREATE FUNCTION coder_transfer_test_reject_config_move() RETURNS trigger
			LANGUAGE plpgsql AS $$
			BEGIN
				RAISE EXCEPTION 'forced transfer failure' USING ERRCODE = 'check_violation';
			END;
			$$
		`)
		mustExec(t, ctx, db, "create failure trigger", `
			CREATE TRIGGER coder_transfer_test_reject_config_move
			BEFORE UPDATE OF user_id ON user_configs
			FOR EACH ROW EXECUTE FUNCTION coder_transfer_test_reject_config_move()
		`)
		t.Cleanup(func() {
			_, _ = db.ExecContext(context.Background(), `
				DROP TRIGGER IF EXISTS coder_transfer_test_reject_config_move ON user_configs
			`)
			_, _ = db.ExecContext(context.Background(), `
				DROP FUNCTION IF EXISTS coder_transfer_test_reject_config_move()
			`)
		})

		_, err = ApplyTransfer(ctx, db, ids.source, ids.target, plan.PlanSHA256)
		if err == nil || err.Error() != "transfer step move user configs failed (SQLSTATE 23514)" {
			t.Fatalf("ApplyTransfer() error = %v, want redacted forced failure", err)
		}
		assertCount(t, ctx, db, "source rollback workspace", 1, `
			SELECT count(*) FROM workspaces WHERE owner_id = $1
		`, ids.source)
		assertCount(t, ctx, db, "target rollback workspace", 0, `
			SELECT count(*) FROM workspaces WHERE owner_id = $1
		`, ids.target)
		assertCount(t, ctx, db, "source rollback config", 1, `
			SELECT count(*) FROM user_configs WHERE user_id = $1
		`, ids.source)
	})
}

func openIntegrationDatabase(t *testing.T) (*sql.DB, context.Context) {
	t.Helper()

	rawURL := strings.TrimSpace(os.Getenv(integrationDatabaseEnv))
	if rawURL == "" {
		t.Skip(integrationDatabaseEnv + " is not set")
	}
	parsed, err := url.Parse(rawURL)
	if err != nil {
		t.Fatalf("parse integration database URL: %v", err)
	}
	host := parsed.Hostname()
	if host != "localhost" && net.ParseIP(host) == nil {
		t.Fatal("integration database must use a loopback host")
	}
	if ip := net.ParseIP(host); ip != nil && !ip.IsLoopback() {
		t.Fatal("integration database must use a loopback host")
	}
	databaseName := strings.TrimPrefix(parsed.Path, "/")
	if !strings.HasPrefix(databaseName, "coder_transfer_test_") {
		t.Fatal("integration database name must start with coder_transfer_test_")
	}

	db, err := sql.Open("postgres", rawURL)
	if err != nil {
		t.Fatalf("open integration database: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	t.Cleanup(cancel)
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("connect to integration database: %v", err)
	}
	if err := validateSchema(ctx, db); err != nil {
		t.Fatalf("validate integration schema: %v", err)
	}
	return db, ctx
}

func seedCompleteFixture(t *testing.T, ctx context.Context, db *sql.DB, ids fixtureIDs) {
	t.Helper()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin fixture transaction: %v", err)
	}
	defer tx.Rollback()
	mustExec(t, ctx, tx, "disable fixture triggers", `SET LOCAL session_replication_role = replica`)
	seedUserPair(t, ctx, tx, ids.source, ids.target)

	mustExec(t, ctx, tx, "insert organization", `
		INSERT INTO organizations (
			id, name, description, created_at, updated_at, display_name,
			default_org_member_roles
		) VALUES ($1, $2, '', now(), now(), 'Transfer test', $3)
	`, ids.organization, "transfer-"+ids.organization.String(), pq.Array([]string{"organization-member"}))
	mustExec(t, ctx, tx, "insert group", `
		INSERT INTO groups (id, name, organization_id)
		VALUES ($1, $2, $3)
	`, ids.group, "transfer-"+ids.group.String(), ids.organization)
	mustExec(t, ctx, tx, "insert source organization membership", `
		INSERT INTO organization_members (user_id, organization_id, created_at, updated_at, roles)
		VALUES ($1, $2, now(), now(), $3)
	`, ids.source, ids.organization, pq.Array([]string{"organization-admin"}))
	mustExec(t, ctx, tx, "insert target organization membership", `
		INSERT INTO organization_members (user_id, organization_id, created_at, updated_at, roles)
		VALUES ($1, $2, now(), now(), $3)
	`, ids.target, ids.organization, pq.Array([]string{"organization-auditor"}))
	mustExec(t, ctx, tx, "insert source group membership", `
		INSERT INTO group_members (user_id, group_id) VALUES ($1, $2)
	`, ids.source, ids.group)
	for index, providerID := range []uuid.UUID{ids.aiProviderOne, ids.aiProviderTwo} {
		mustExec(t, ctx, tx, "insert AI provider", `
			INSERT INTO ai_providers (id, type, name, base_url)
			VALUES ($1, 'openai', $2, 'https://example.invalid')
		`, providerID, "test-provider-"+string(rune('a'+index))+"-"+providerID.String())
	}
	mustExec(t, ctx, tx, "insert chat model config", `
		INSERT INTO chat_model_configs (
			id, model, context_limit, compression_threshold, ai_provider_id,
			created_by, updated_by
		) VALUES ($1, 'test-model', 100000, 80, $2, $3, $4)
	`, ids.modelConfig, ids.aiProviderOne, ids.source, ids.target)
	mustExec(t, ctx, tx, "insert MCP server config", `
		INSERT INTO mcp_server_configs (
			id, display_name, slug, url, created_by, updated_by
		) VALUES ($1, 'Transfer test', $2, 'https://example.invalid', $3, $4)
	`, ids.mcpConfig, "transfer-"+ids.mcpConfig.String(), ids.source, ids.target)
	mustExec(t, ctx, tx, "insert template", `
		INSERT INTO templates (
			id, created_at, updated_at, organization_id, name, provisioner,
			active_version_id, created_by, user_acl
		) VALUES ($1, now(), now(), $2, $3, 'terraform', $4, $5, $6::jsonb)
	`, ids.template, ids.organization, "template-"+ids.template.String(), ids.templateVersion, ids.source,
		userACL(ids.source, []string{"read", "use"}, ids.target, []string{"read", "update"}))
	mustExec(t, ctx, tx, "insert workspace", `
		INSERT INTO workspaces (
			id, created_at, updated_at, owner_id, organization_id, template_id,
			name, user_acl
		) VALUES ($1, now(), now(), $2, $3, $4, $5, $6::jsonb)
	`, ids.workspace, ids.source, ids.organization, ids.template,
		"workspace-"+ids.workspace.String(),
		userACLEntries(ids.source, []string{"read", "update"}, ids.target, []string{"read"}))
	mustExec(t, ctx, tx, "insert task", `
		INSERT INTO tasks (
			id, organization_id, owner_id, name, workspace_id,
			template_version_id, prompt, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, 'test prompt', now())
	`, ids.task, ids.organization, ids.source, "task-"+ids.task.String(), ids.workspace, ids.templateVersion)
	mustExec(t, ctx, tx, "insert chat", `
		INSERT INTO chats (
			id, owner_id, workspace_id, last_model_config_id, organization_id,
			user_acl
		) VALUES ($1, $2, $3, $4, $5, $6::jsonb)
	`, ids.chat, ids.source, ids.workspace, ids.modelConfig, ids.organization,
		userACLEntries(ids.source, []string{"read", "update"}, ids.target, []string{"read"}))
	for _, creatorID := range []uuid.UUID{ids.source, ids.target} {
		mustExec(t, ctx, tx, "insert chat message", `
			INSERT INTO chat_messages (
				chat_id, created_by, role, content, content_version, revision
			) VALUES ($1, $2, 'user', '{}'::jsonb, 1, 1)
		`, ids.chat, creatorID)
		mustExec(t, ctx, tx, "insert queued chat message", `
			INSERT INTO chat_queued_messages (chat_id, content, created_by)
			VALUES ($1, '{}'::jsonb, $2)
		`, ids.chat, creatorID)
	}
	mustExec(t, ctx, tx, "insert chat file", `
		INSERT INTO chat_files (id, owner_id, organization_id, name, mimetype, data)
		VALUES ($1, $2, $3, 'fixture', 'text/plain', decode('01', 'hex'))
	`, ids.chatFile, ids.source, ids.organization)
	mustExec(t, ctx, tx, "insert source file", `
		INSERT INTO files (id, hash, created_at, created_by, mimetype, data)
		VALUES ($1, $2, now(), $3, 'application/x-tar', decode('01', 'hex'))
	`, ids.fileOne, strings.Repeat("a", 64), ids.source)
	mustExec(t, ctx, tx, "insert target file", `
		INSERT INTO files (id, hash, created_at, created_by, mimetype, data)
		VALUES ($1, $2, now(), $3, 'application/x-tar', decode('02', 'hex'))
	`, ids.fileTwo, strings.Repeat("b", 64), ids.target)
	mustExec(t, ctx, tx, "insert external auth link", `
		INSERT INTO external_auth_links (
			provider_id, user_id, created_at, updated_at, oauth_access_token,
			oauth_refresh_token, oauth_expiry
		) VALUES ('github', $1, now(), now(), 'access', 'refresh', now())
	`, ids.source)
	mustExec(t, ctx, tx, "insert MCP token", `
		INSERT INTO mcp_server_user_tokens (
			id, mcp_server_config_id, user_id, access_token
		) VALUES ($1, $2, $3, 'access')
	`, uuid.New(), ids.mcpConfig, ids.source)
	for _, config := range []struct {
		user  uuid.UUID
		key   string
		value string
	}{
		{ids.source, "same", "same-value"},
		{ids.source, "source-only", "source-value"},
		{ids.target, "same", "same-value"},
		{ids.target, "target-only", "target-value"},
	} {
		mustExec(t, ctx, tx, "insert user config", `
			INSERT INTO user_configs (user_id, key, value) VALUES ($1, $2, $3)
		`, config.user, config.key, config.value)
	}
	mustExec(t, ctx, tx, "insert source secret", `
		INSERT INTO user_secrets (
			id, user_id, name, description, value, env_name
		) VALUES ($1, $2, 'source-secret', '', 'source-value', 'SOURCE_SECRET')
	`, uuid.New(), ids.source)
	mustExec(t, ctx, tx, "insert target secret", `
		INSERT INTO user_secrets (
			id, user_id, name, description, value, env_name
		) VALUES ($1, $2, 'target-secret', '', 'target-value', 'TARGET_SECRET')
	`, uuid.New(), ids.target)
	mustExec(t, ctx, tx, "insert source skill", `
		INSERT INTO user_skills (id, user_id, name, content)
		VALUES ($1, $2, 'source-skill', 'source content')
	`, uuid.New(), ids.source)
	mustExec(t, ctx, tx, "insert target skill", `
		INSERT INTO user_skills (id, user_id, name, content)
		VALUES ($1, $2, 'target-skill', 'target content')
	`, uuid.New(), ids.target)
	mustExec(t, ctx, tx, "insert source AI provider key", `
		INSERT INTO user_ai_provider_keys (id, user_id, ai_provider_id, api_key)
		VALUES ($1, $2, $3, 'source-key')
	`, uuid.New(), ids.source, ids.aiProviderOne)
	mustExec(t, ctx, tx, "insert target AI provider key", `
		INSERT INTO user_ai_provider_keys (id, user_id, ai_provider_id, api_key)
		VALUES ($1, $2, $3, 'target-key')
	`, uuid.New(), ids.target, ids.aiProviderTwo)
	mustExec(t, ctx, tx, "insert source notification preference", `
		INSERT INTO notification_preferences (user_id, notification_template_id, disabled)
		VALUES ($1, $2, true)
	`, ids.source, ids.notification)
	mustExec(t, ctx, tx, "insert target notification preference", `
		INSERT INTO notification_preferences (user_id, notification_template_id, disabled)
		VALUES ($1, $2, true)
	`, ids.target, ids.notification)
	mustExec(t, ctx, tx, "insert source AI budget", `
		INSERT INTO user_ai_budget_overrides (user_id, group_id, spend_limit_micros)
		VALUES ($1, $2, 1000)
	`, ids.source, ids.group)
	mustExec(t, ctx, tx, "insert target AI budget", `
		INSERT INTO user_ai_budget_overrides (user_id, group_id, spend_limit_micros)
		VALUES ($1, $2, 1000)
	`, ids.target, ids.group)
	mustExec(t, ctx, tx, "insert source AI seat state", `
		INSERT INTO ai_seat_state (
			user_id, first_used_at, last_used_at, last_event_type,
			last_event_description, updated_at
		) VALUES ($1, now() - interval '2 days', now(), 'aibridge', 'source event', now())
	`, ids.source)
	mustExec(t, ctx, tx, "insert target AI seat state", `
		INSERT INTO ai_seat_state (
			user_id, first_used_at, last_used_at, last_event_type,
			last_event_description, updated_at
		) VALUES ($1, now() - interval '1 day', now() - interval '12 hours', 'task', 'target event', now())
	`, ids.target)
	seedRetainedAuthentication(t, ctx, tx, ids.source, "source-"+ids.source.String(), "github", "01")
	seedRetainedAuthentication(t, ctx, tx, ids.target, "target-"+ids.target.String(), "oidc", "02")

	if err := tx.Commit(); err != nil {
		t.Fatalf("commit complete fixture: %v", err)
	}
}

func seedWorkspaceConflictFixture(t *testing.T, ctx context.Context, db *sql.DB, ids fixtureIDs) {
	t.Helper()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin conflict fixture: %v", err)
	}
	defer tx.Rollback()
	mustExec(t, ctx, tx, "disable conflict fixture triggers", `SET LOCAL session_replication_role = replica`)
	seedUserPair(t, ctx, tx, ids.source, ids.target)
	name := "conflict-" + ids.workspace.String()
	for _, ownerID := range []uuid.UUID{ids.source, ids.target} {
		mustExec(t, ctx, tx, "insert conflict workspace", `
			INSERT INTO workspaces (
				id, created_at, updated_at, owner_id, organization_id,
				template_id, name
			) VALUES ($1, now(), now(), $2, $3, $4, $5)
		`, uuid.New(), ownerID, ids.organization, ids.template, name)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit conflict fixture: %v", err)
	}
}

func seedRollbackFixture(t *testing.T, ctx context.Context, db *sql.DB, ids fixtureIDs) {
	t.Helper()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("begin rollback fixture: %v", err)
	}
	defer tx.Rollback()
	mustExec(t, ctx, tx, "disable rollback fixture triggers", `SET LOCAL session_replication_role = replica`)
	seedUserPair(t, ctx, tx, ids.source, ids.target)
	mustExec(t, ctx, tx, "insert rollback workspace", `
		INSERT INTO workspaces (
			id, created_at, updated_at, owner_id, organization_id,
			template_id, name
		) VALUES ($1, now(), now(), $2, $3, $4, $5)
	`, ids.workspace, ids.source, ids.organization, ids.template, "rollback-"+ids.workspace.String())
	mustExec(t, ctx, tx, "insert rollback config", `
		INSERT INTO user_configs (user_id, key, value)
		VALUES ($1, 'rollback', 'value')
	`, ids.source)
	if err := tx.Commit(); err != nil {
		t.Fatalf("commit rollback fixture: %v", err)
	}
}

func seedUserPair(t *testing.T, ctx context.Context, tx *sql.Tx, sourceID, targetID uuid.UUID) {
	t.Helper()

	users := []struct {
		id        uuid.UUID
		prefix    string
		roles     []string
		loginType string
	}{
		{sourceID, "source", []string{"owner"}, "github"},
		{targetID, "target", []string{"member-auditor"}, "oidc"},
	}
	for _, user := range users {
		mustExec(t, ctx, tx, "insert user", `
			INSERT INTO users (
				id, email, username, hashed_password, created_at, updated_at,
				status, rbac_roles, login_type
			) VALUES (
				$1, $2, $3, decode('', 'hex'), now(), now(),
				'active', $4, $5::login_type
			)
		`, user.id, user.prefix+"-"+user.id.String()+"@example.invalid",
			user.prefix+"-"+user.id.String(), pq.Array(user.roles), user.loginType)
		mustExec(t, ctx, tx, "insert identity link", `
			INSERT INTO user_links (user_id, login_type, linked_id)
			VALUES ($1, $2::login_type, $3)
		`, user.id, user.loginType, user.prefix+"-identity-"+user.id.String())
	}
}

func seedRetainedAuthentication(
	t *testing.T,
	ctx context.Context,
	tx *sql.Tx,
	userID uuid.UUID,
	prefix string,
	loginType string,
	hashedSecret string,
) {
	t.Helper()

	mustExec(t, ctx, tx, "insert retained API key", `
		INSERT INTO api_keys (
			id, hashed_secret, user_id, last_used, expires_at, created_at,
			updated_at, login_type, scopes, allow_list
		) VALUES (
			$1, decode($2, 'hex'), $3, now(), now() + interval '1 day', now(),
			now(), $4::login_type, ARRAY['coder:all']::api_key_scope[], ARRAY['*']
		)
	`, prefix+"-api-key", hashedSecret, userID, loginType)
	mustExec(t, ctx, tx, "insert retained SSH key", `
		INSERT INTO gitsshkeys (
			user_id, created_at, updated_at, private_key, public_key
		) VALUES ($1, now(), now(), $2, $3)
	`, userID, prefix+"-private-key", prefix+"-public-key")
}

func assertSuccessfulTransfer(
	t *testing.T,
	ctx context.Context,
	db *sql.DB,
	ids fixtureIDs,
	sourceExternalAuth int64,
	targetExternalAuth int64,
) {
	t.Helper()

	for _, owner := range []struct {
		name  string
		table string
	}{
		{"workspace", "workspaces"},
		{"task", "tasks"},
		{"chat", "chats"},
		{"chat file", "chat_files"},
	} {
		assertCount(t, ctx, db, owner.name+" target ownership", 1,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(owner.table)+` WHERE owner_id = $1`, ids.target)
		assertCount(t, ctx, db, owner.name+" source ownership", 0,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(owner.table)+` WHERE owner_id = $1`, ids.source)
	}
	assertCount(t, ctx, db, "target external auth links", targetExternalAuth,
		`SELECT count(*) FROM external_auth_links WHERE user_id = $1`, ids.target)
	assertCount(t, ctx, db, "source external auth links", sourceExternalAuth,
		`SELECT count(*) FROM external_auth_links WHERE user_id = $1`, ids.source)
	for _, resource := range []struct {
		name  string
		table string
		want  int64
	}{
		{"MCP tokens", "mcp_server_user_tokens", 1},
		{"user configs", "user_configs", 3},
		{"user secrets", "user_secrets", 2},
		{"user skills", "user_skills", 2},
		{"AI provider keys", "user_ai_provider_keys", 2},
		{"notification preferences", "notification_preferences", 1},
		{"AI budget overrides", "user_ai_budget_overrides", 1},
		{"AI seat state", "ai_seat_state", 1},
	} {
		assertCount(t, ctx, db, resource.name+" target records", resource.want,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(resource.table)+` WHERE user_id = $1`, ids.target)
		assertCount(t, ctx, db, resource.name+" source records", 0,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(resource.table)+` WHERE user_id = $1`, ids.source)
	}
	for _, resource := range []struct {
		name  string
		table string
		want  int64
	}{
		{"chat messages", "chat_messages", 2},
		{"queued chat messages", "chat_queued_messages", 2},
		{"files", "files", 2},
	} {
		assertCount(t, ctx, db, resource.name+" target records", resource.want,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(resource.table)+` WHERE created_by = $1`, ids.target)
		assertCount(t, ctx, db, resource.name+" source records", 0,
			`SELECT count(*) FROM `+pq.QuoteIdentifier(resource.table)+` WHERE created_by = $1`, ids.source)
	}

	assertTrue(t, ctx, db, "site roles copied", `
		SELECT rbac_roles @> ARRAY['owner', 'member-auditor']::text[]
		FROM users WHERE id = $1
	`, ids.target)
	assertTrue(t, ctx, db, "organization roles copied", `
		SELECT roles @> ARRAY['organization-admin', 'organization-auditor']::text[]
		FROM organization_members WHERE user_id = $1 AND organization_id = $2
	`, ids.target, ids.organization)
	assertCount(t, ctx, db, "target group membership", 1, `
		SELECT count(*) FROM group_members WHERE user_id = $1 AND group_id = $2
	`, ids.target, ids.group)
	assertTrue(t, ctx, db, "template ACL copied", `
		SELECT (user_acl -> $1::text) @> '["use", "update"]'::jsonb
		FROM templates WHERE id = $2
	`, ids.target, ids.template)
	assertTrue(t, ctx, db, "workspace ACL copied", `
		SELECT (user_acl -> $1::text -> 'permissions') @> '["read", "update"]'::jsonb
		FROM workspaces WHERE id = $2
	`, ids.target, ids.workspace)
	assertTrue(t, ctx, db, "chat ACL copied", `
		SELECT (user_acl -> $1::text -> 'permissions') @> '["read", "update"]'::jsonb
		FROM chats WHERE id = $2
	`, ids.target, ids.chat)
	assertTrue(t, ctx, db, "AI seat state merged", `
		SELECT last_event_type = 'aibridge' AND last_event_description = 'source event'
		FROM ai_seat_state WHERE user_id = $1
	`, ids.target)
	assertTrue(t, ctx, db, "chat model attribution retained", `
		SELECT created_by = $1 AND updated_by = $2
		FROM chat_model_configs WHERE id = $3
	`, ids.source, ids.target, ids.modelConfig)
	assertTrue(t, ctx, db, "MCP server attribution retained", `
		SELECT created_by = $1 AND updated_by = $2
		FROM mcp_server_configs WHERE id = $3
	`, ids.source, ids.target, ids.mcpConfig)

	assertTrue(t, ctx, db, "users and login types unchanged", `
		SELECT
			(SELECT NOT deleted AND login_type = 'github' FROM users WHERE id = $1)
			AND
			(SELECT NOT deleted AND login_type = 'oidc' FROM users WHERE id = $2)
	`, ids.source, ids.target)
	assertTrue(t, ctx, db, "identity links unchanged", `
		SELECT
			(SELECT count(*) = 1 FROM user_links WHERE user_id = $1 AND login_type = 'github')
			AND
			(SELECT count(*) = 1 FROM user_links WHERE user_id = $2 AND login_type = 'oidc')
	`, ids.source, ids.target)
	assertCount(t, ctx, db, "source retained API key", 1, `
		SELECT count(*) FROM api_keys WHERE user_id = $1
	`, ids.source)
	assertCount(t, ctx, db, "target retained API key", 1, `
		SELECT count(*) FROM api_keys WHERE user_id = $1
	`, ids.target)
	assertCount(t, ctx, db, "source retained SSH key", 1, `
		SELECT count(*) FROM gitsshkeys WHERE user_id = $1
	`, ids.source)
	assertCount(t, ctx, db, "source membership retained", 1, `
		SELECT count(*) FROM organization_members WHERE user_id = $1 AND organization_id = $2
	`, ids.source, ids.organization)
}

type testExecer interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

func mustExec(t *testing.T, ctx context.Context, execer testExecer, name, query string, args ...any) {
	t.Helper()
	if _, err := execer.ExecContext(ctx, query, args...); err != nil {
		t.Fatalf("%s: %v", name, publicDatabaseError(name, err))
	}
}

func assertCount(
	t *testing.T,
	ctx context.Context,
	db *sql.DB,
	name string,
	want int64,
	query string,
	args ...any,
) {
	t.Helper()
	var got int64
	if err := db.QueryRowContext(ctx, query, args...).Scan(&got); err != nil {
		t.Fatalf("query %s: %v", name, publicDatabaseError(name, err))
	}
	if got != want {
		t.Fatalf("%s count = %d, want %d", name, got, want)
	}
}

func assertTrue(t *testing.T, ctx context.Context, db *sql.DB, name, query string, args ...any) {
	t.Helper()
	var got bool
	if err := db.QueryRowContext(ctx, query, args...).Scan(&got); err != nil {
		t.Fatalf("query %s: %v", name, publicDatabaseError(name, err))
	}
	if !got {
		t.Fatalf("%s = false, want true", name)
	}
}

func assertPlannedCounts(t *testing.T, plan Plan, resource string, source, target int64) {
	t.Helper()
	for _, counts := range plan.Transfers {
		if counts.Resource == resource {
			if counts.Source != source || counts.Target != target {
				t.Fatalf(
					"plan %s counts = (%d, %d), want (%d, %d)",
					resource,
					counts.Source,
					counts.Target,
					source,
					target,
				)
			}
			return
		}
	}
	t.Fatalf("plan does not contain %s", resource)
}

func assertRetainedCounts(t *testing.T, plan Plan, resource string, source, target int64) {
	t.Helper()
	for _, counts := range plan.Retained {
		if counts.Resource == resource {
			if counts.Source != source || counts.Target != target {
				t.Fatalf(
					"plan retained %s counts = (%d, %d), want (%d, %d)",
					resource,
					counts.Source,
					counts.Target,
					source,
					target,
				)
			}
			return
		}
	}
	t.Fatalf("plan retained data does not contain %s", resource)
}

func assertSourceRetainedCount(t *testing.T, plan Plan, resource string, want int64) {
	t.Helper()
	for _, count := range plan.SourceRetained {
		if count.Resource == resource {
			if count.Count != want {
				t.Fatalf("plan source-retained %s count = %d, want %d", resource, count.Count, want)
			}
			return
		}
	}
	t.Fatalf("plan source-retained data does not contain %s", resource)
}

func assertUserReferenceInventory(t *testing.T, ctx context.Context, db *sql.DB) {
	t.Helper()

	classified := map[string]string{
		"ai_seat_state.user_id":                "transfer",
		"aibridge_interceptions.initiator_id":  "retain",
		"api_keys.user_id":                     "retain",
		"audit_logs.user_id":                   "retain",
		"boundary_logs.owner_id":               "retain",
		"boundary_sessions.owner_id":           "retain",
		"chat_files.owner_id":                  "transfer",
		"chat_messages.created_by":             "transfer",
		"chat_model_configs.created_by":        "retain",
		"chat_model_configs.updated_by":        "retain",
		"chat_queued_messages.created_by":      "transfer",
		"chats.owner_id":                       "transfer",
		"connection_logs.user_id":              "retain",
		"connection_logs.workspace_owner_id":   "retain",
		"external_auth_links.user_id":          "transfer",
		"files.created_by":                     "transfer",
		"gitsshkeys.user_id":                   "retain",
		"group_members.user_id":                "copy",
		"inbox_notifications.user_id":          "retain",
		"mcp_server_configs.created_by":        "retain",
		"mcp_server_configs.updated_by":        "retain",
		"mcp_server_user_tokens.user_id":       "transfer",
		"notification_messages.user_id":        "retain",
		"notification_preferences.user_id":     "transfer",
		"oauth2_provider_app_codes.user_id":    "retain",
		"oauth2_provider_app_tokens.user_id":   "retain",
		"organization_members.user_id":         "copy",
		"provisioner_jobs.initiator_id":        "retain",
		"tasks.owner_id":                       "transfer",
		"template_usage_stats.user_id":         "retain",
		"template_versions.created_by":         "retain",
		"templates.created_by":                 "retain",
		"user_ai_budget_overrides.user_id":     "transfer",
		"user_ai_provider_keys.user_id":        "transfer",
		"user_configs.user_id":                 "transfer",
		"user_deleted.user_id":                 "retain",
		"user_links.user_id":                   "retain",
		"user_secrets.user_id":                 "transfer",
		"user_skills.user_id":                  "transfer",
		"user_status_changes.user_id":          "retain",
		"webpush_subscriptions.user_id":        "retain",
		"workspace_agent_stats.user_id":        "retain",
		"workspace_app_audit_sessions.user_id": "ephemeral",
		"workspace_app_stats.user_id":          "retain",
		"workspace_builds.initiator_id":        "retain",
		"workspaces.owner_id":                  "transfer",
	}

	rows, err := db.QueryContext(ctx, `
		SELECT columns.table_name, columns.column_name
		FROM information_schema.columns AS columns
		JOIN information_schema.tables AS tables
		  ON tables.table_schema = columns.table_schema
		 AND tables.table_name = columns.table_name
		WHERE columns.table_schema = 'public'
		  AND tables.table_type = 'BASE TABLE'
		  AND columns.data_type = 'uuid'
		  AND columns.column_name = ANY($1)
		ORDER BY columns.table_name, columns.ordinal_position
	`, pq.Array([]string{
		"created_by",
		"initiator_id",
		"owner_id",
		"updated_by",
		"user_id",
		"workspace_owner_id",
	}))
	if err != nil {
		t.Fatalf("query user reference inventory: %v", publicDatabaseError("query user reference inventory", err))
	}
	defer rows.Close()

	seen := make(map[string]struct{}, len(classified))
	for rows.Next() {
		var table, column string
		if err := rows.Scan(&table, &column); err != nil {
			t.Fatalf("scan user reference inventory: %v", publicDatabaseError("scan user reference inventory", err))
		}
		key := table + "." + column
		if _, ok := classified[key]; !ok {
			t.Fatalf("unclassified user reference: %s", key)
		}
		seen[key] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterate user reference inventory: %v", publicDatabaseError("iterate user reference inventory", err))
	}

	missing := make([]string, 0)
	for key := range classified {
		if _, ok := seen[key]; !ok {
			missing = append(missing, key)
		}
	}
	if len(missing) != 0 {
		sort.Strings(missing)
		t.Fatalf("classified user references missing from schema: %s", strings.Join(missing, ", "))
	}
}

func userACL(sourceID uuid.UUID, sourceActions []string, targetID uuid.UUID, targetActions []string) string {
	return `{"` + sourceID.String() + `":["` + strings.Join(sourceActions, `","`) + `"],"` +
		targetID.String() + `":["` + strings.Join(targetActions, `","`) + `"]}`
}

func userACLEntries(sourceID uuid.UUID, sourceActions []string, targetID uuid.UUID, targetActions []string) string {
	return `{"` + sourceID.String() + `":{"permissions":["` + strings.Join(sourceActions, `","`) +
		`"]},"` + targetID.String() + `":{"permissions":["` + strings.Join(targetActions, `","`) + `"]}}`
}
