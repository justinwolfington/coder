package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sort"

	"github.com/google/uuid"
	"github.com/lib/pq"
)

const (
	expectedSchemaVersion = 535
	transferAdvisoryLock  = int64(77825243733537201)
)

type ResourceCounts struct {
	Resource string `json:"resource"`
	Source   int64  `json:"source"`
	Target   int64  `json:"target"`
}

type ResourceCount struct {
	Resource string `json:"resource"`
	Count    int64  `json:"count"`
}

type Conflict struct {
	Kind  string `json:"kind"`
	Count int64  `json:"count"`
}

type Plan struct {
	SchemaVersion  int              `json:"schema_version"`
	Transfers      []ResourceCounts `json:"transfers"`
	AccessCopies   []ResourceCount  `json:"access_copies"`
	Merges         []ResourceCount  `json:"identical_record_merges"`
	SourceRetained []ResourceCount  `json:"source_retained"`
	Retained       []ResourceCounts `json:"retained"`
	Conflicts      []Conflict       `json:"conflicts"`
	PlanSHA256     string           `json:"plan_sha256"`
	Applied        bool             `json:"applied"`
}

type queryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

type namedQuery struct {
	name  string
	query string
}

var transferCountQueries = []namedQuery{
	{"workspaces", `SELECT count(*) FROM workspaces WHERE owner_id = $1`},
	{"tasks", `SELECT count(*) FROM tasks WHERE owner_id = $1`},
	{"chats", `SELECT count(*) FROM chats WHERE owner_id = $1`},
	{"chat_messages", `SELECT count(*) FROM chat_messages WHERE created_by = $1`},
	{"chat_queued_messages", `SELECT count(*) FROM chat_queued_messages WHERE created_by = $1`},
	{"chat_files", `SELECT count(*) FROM chat_files WHERE owner_id = $1`},
	{"files", `SELECT count(*) FROM files WHERE created_by = $1`},
	{"external_auth_links", `SELECT count(*) FROM external_auth_links WHERE user_id = $1`},
	{"mcp_server_user_tokens", `SELECT count(*) FROM mcp_server_user_tokens WHERE user_id = $1`},
	{"user_configs", `SELECT count(*) FROM user_configs WHERE user_id = $1`},
	{"user_secrets", `SELECT count(*) FROM user_secrets WHERE user_id = $1`},
	{"user_skills", `SELECT count(*) FROM user_skills WHERE user_id = $1`},
	{"user_ai_provider_keys", `SELECT count(*) FROM user_ai_provider_keys WHERE user_id = $1`},
	{"notification_preferences", `SELECT count(*) FROM notification_preferences WHERE user_id = $1`},
	{"user_ai_budget_overrides", `SELECT count(*) FROM user_ai_budget_overrides WHERE user_id = $1`},
	{"ai_seat_state", `SELECT count(*) FROM ai_seat_state WHERE user_id = $1`},
}

var accessCopyCountQueries = []namedQuery{
	{"site_roles", `SELECT cardinality(rbac_roles)::bigint FROM users WHERE id = $1`},
	{"organization_memberships", `SELECT count(*) FROM organization_members WHERE user_id = $1`},
	{"group_memberships", `SELECT count(*) FROM group_members WHERE user_id = $1`},
	{"template_acl_grants", `SELECT count(*) FROM templates WHERE user_acl ? $1::text`},
	{"workspace_acl_grants", `SELECT count(*) FROM workspaces WHERE user_acl ? $1::text`},
	{"chat_acl_grants", `SELECT count(*) FROM chats WHERE user_acl ? $1::text`},
}

var retainedCountQueries = []namedQuery{
	{"api_keys", `SELECT count(*) FROM api_keys WHERE user_id = $1`},
	{"identity_links", `SELECT count(*) FROM user_links WHERE user_id = $1`},
	{"git_ssh_keys", `SELECT count(*) FROM gitsshkeys WHERE user_id = $1`},
	{"oauth2_provider_app_codes", `SELECT count(*) FROM oauth2_provider_app_codes WHERE user_id = $1`},
	{"oauth2_provider_app_tokens", `SELECT count(*) FROM oauth2_provider_app_tokens WHERE user_id = $1`},
	{"inbox_notifications", `SELECT count(*) FROM inbox_notifications WHERE user_id = $1`},
	{"notification_messages", `SELECT count(*) FROM notification_messages WHERE user_id = $1`},
	{"webpush_subscriptions", `SELECT count(*) FROM webpush_subscriptions WHERE user_id = $1`},
	{"audit_logs", `SELECT count(*) FROM audit_logs WHERE user_id = $1`},
	{"workspace_build_attribution", `SELECT count(*) FROM workspace_builds WHERE initiator_id = $1`},
	{"provisioner_job_attribution", `SELECT count(*) FROM provisioner_jobs WHERE initiator_id = $1`},
	{"template_attribution", `SELECT count(*) FROM templates WHERE created_by = $1`},
	{"template_version_attribution", `SELECT count(*) FROM template_versions WHERE created_by = $1`},
	{"user_status_history", `SELECT count(*) FROM user_status_changes WHERE user_id = $1`},
	{"connection_history", `SELECT count(*) FROM connection_logs WHERE user_id = $1 OR workspace_owner_id = $1`},
	{"workspace_agent_usage", `SELECT count(*) FROM workspace_agent_stats WHERE user_id = $1`},
	{"workspace_app_usage", `SELECT count(*) FROM workspace_app_stats WHERE user_id = $1`},
	{"template_usage", `SELECT count(*) FROM template_usage_stats WHERE user_id = $1`},
	{"aibridge_history", `SELECT count(*) FROM aibridge_interceptions WHERE initiator_id = $1`},
	{"boundary_sessions", `SELECT count(*) FROM boundary_sessions WHERE owner_id = $1`},
	{"boundary_logs", `SELECT count(*) FROM boundary_logs WHERE owner_id = $1`},
	{"chat_model_config_attribution", `SELECT count(*) FROM chat_model_configs WHERE created_by = $1 OR updated_by = $1`},
	{"mcp_server_config_attribution", `SELECT count(*) FROM mcp_server_configs WHERE created_by = $1 OR updated_by = $1`},
	{"user_deletion_history", `SELECT count(*) FROM user_deleted WHERE user_id = $1`},
}

var mergeCountQueries = []namedQuery{
	{"user_configs", `
		SELECT count(*)
		FROM user_configs AS source
		JOIN user_configs AS target
		  ON target.user_id = $2
		 AND target.key = source.key
		 AND target.value = source.value
		WHERE source.user_id = $1
	`},
	{"notification_preferences", `
		SELECT count(*)
		FROM notification_preferences AS source
		JOIN notification_preferences AS target
		  ON target.user_id = $2
		 AND target.notification_template_id = source.notification_template_id
		 AND target.disabled = source.disabled
		WHERE source.user_id = $1
	`},
	{"user_ai_budget_overrides", `
		SELECT count(*)
		FROM user_ai_budget_overrides AS source
		JOIN user_ai_budget_overrides AS target
		  ON target.user_id = $2
		 AND (target.group_id, target.spend_limit_micros)
		     IS NOT DISTINCT FROM (source.group_id, source.spend_limit_micros)
		WHERE source.user_id = $1
	`},
	{"ai_seat_state", `
		SELECT count(*)
		FROM ai_seat_state AS source
		JOIN ai_seat_state AS target ON target.user_id = $2
		WHERE source.user_id = $1
	`},
}

var sourceRetainedCountQueries = []namedQuery{
	{"external_auth_links", `
		SELECT count(*)
		FROM external_auth_links AS source
		WHERE source.user_id = $1
		  AND EXISTS (
			SELECT 1
			FROM external_auth_links AS target
			WHERE target.user_id = $2
			  AND target.provider_id = source.provider_id
		  )
	`},
}

var conflictQueries = []namedQuery{
	{"active_workspace_name", `
		SELECT count(*)
		FROM workspaces AS source
		JOIN workspaces AS target
		  ON target.owner_id = $2
		 AND target.deleted = false
		 AND lower(target.name) = lower(source.name)
		WHERE source.owner_id = $1 AND source.deleted = false
	`},
	{"active_task_name", `
		SELECT count(*)
		FROM tasks AS source
		JOIN tasks AS target
		  ON target.owner_id = $2
		 AND target.deleted_at IS NULL
		 AND lower(target.name) = lower(source.name)
		WHERE source.owner_id = $1 AND source.deleted_at IS NULL
	`},
	{"file_hash", `
		SELECT count(*)
		FROM files AS source
		JOIN files AS target
		  ON target.created_by = $2 AND target.hash = source.hash
		WHERE source.created_by = $1
	`},
	{"mcp_server_token", `
		SELECT count(*)
		FROM mcp_server_user_tokens AS source
		JOIN mcp_server_user_tokens AS target
		  ON target.user_id = $2
		 AND target.mcp_server_config_id = source.mcp_server_config_id
		WHERE source.user_id = $1
	`},
	{"user_config_value", `
		SELECT count(*)
		FROM user_configs AS source
		JOIN user_configs AS target
		  ON target.user_id = $2 AND target.key = source.key
		WHERE source.user_id = $1 AND source.value IS DISTINCT FROM target.value
	`},
	{"user_secret_identifier", `
		SELECT count(*)
		FROM user_secrets AS source
		JOIN user_secrets AS target
		  ON target.user_id = $2
		 AND (
			target.name = source.name
			OR (source.env_name <> '' AND target.env_name = source.env_name)
			OR (source.file_path <> '' AND target.file_path = source.file_path)
		 )
		WHERE source.user_id = $1
	`},
	{"user_secret_count_limit", `
		SELECT greatest(count(*) - 50, 0)::bigint
		FROM user_secrets WHERE user_id IN ($1, $2)
	`},
	{"user_secret_total_bytes_limit", `
		SELECT greatest(coalesce(sum(octet_length(value)), 0) - 204800, 0)::bigint
		FROM user_secrets WHERE user_id IN ($1, $2)
	`},
	{"user_secret_env_bytes_limit", `
		SELECT greatest(coalesce(sum(octet_length(value)) FILTER (WHERE env_name <> ''), 0) - 24576, 0)::bigint
		FROM user_secrets WHERE user_id IN ($1, $2)
	`},
	{"user_skill_name", `
		SELECT count(*)
		FROM user_skills AS source
		JOIN user_skills AS target
		  ON target.user_id = $2 AND target.name = source.name
		WHERE source.user_id = $1
	`},
	{"user_skill_count_limit", `
		SELECT greatest(count(*) - 100, 0)::bigint
		FROM user_skills WHERE user_id IN ($1, $2)
	`},
	{"ai_provider_key", `
		SELECT count(*)
		FROM user_ai_provider_keys AS source
		JOIN user_ai_provider_keys AS target
		  ON target.user_id = $2 AND target.ai_provider_id = source.ai_provider_id
		WHERE source.user_id = $1
	`},
	{"notification_preference", `
		SELECT count(*)
		FROM notification_preferences AS source
		JOIN notification_preferences AS target
		  ON target.user_id = $2
		 AND target.notification_template_id = source.notification_template_id
		WHERE source.user_id = $1 AND source.disabled IS DISTINCT FROM target.disabled
	`},
	{"ai_budget_override", `
		SELECT count(*)
		FROM user_ai_budget_overrides AS source
		JOIN user_ai_budget_overrides AS target ON target.user_id = $2
		WHERE source.user_id = $1
		  AND (source.group_id, source.spend_limit_micros)
		      IS DISTINCT FROM (target.group_id, target.spend_limit_micros)
	`},
}

func CreatePlan(
	ctx context.Context,
	db *sql.DB,
	sourceID uuid.UUID,
	targetID uuid.UUID,
) (Plan, error) {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{
		Isolation: sql.LevelRepeatableRead,
		ReadOnly:  true,
	})
	if err != nil {
		return Plan{}, publicDatabaseError("start plan transaction", err)
	}
	defer tx.Rollback()

	plan, err := buildPlan(ctx, tx, sourceID, targetID, false)
	if err != nil {
		return Plan{}, err
	}
	if err := tx.Commit(); err != nil {
		return Plan{}, publicDatabaseError("commit plan transaction", err)
	}
	return plan, nil
}

func ApplyTransfer(
	ctx context.Context,
	db *sql.DB,
	sourceID uuid.UUID,
	targetID uuid.UUID,
	expectedPlanSHA256 string,
) (Plan, error) {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return Plan{}, publicDatabaseError("start transfer transaction", err)
	}
	defer tx.Rollback()

	for _, statement := range []string{
		`SET LOCAL lock_timeout = '10s'`,
		`SET LOCAL statement_timeout = '90s'`,
	} {
		if _, err := tx.ExecContext(ctx, statement); err != nil {
			return Plan{}, publicDatabaseError("configure transfer transaction", err)
		}
	}
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock($1)`, transferAdvisoryLock); err != nil {
		return Plan{}, publicDatabaseError("lock transfer operation", err)
	}

	plan, err := buildPlan(ctx, tx, sourceID, targetID, true)
	if err != nil {
		return Plan{}, err
	}
	if plan.PlanSHA256 != expectedPlanSHA256 {
		return Plan{}, errors.New("plan-sha256 does not match the current database state")
	}
	if len(plan.Conflicts) != 0 {
		return Plan{}, errors.New("transfer plan contains conflicts")
	}

	if err := executeTransfer(ctx, tx, sourceID, targetID); err != nil {
		return Plan{}, err
	}
	if err := verifyTransfer(ctx, tx, sourceID, targetID, plan); err != nil {
		return Plan{}, err
	}
	if err := validateUserPair(ctx, tx, sourceID, targetID, true); err != nil {
		return Plan{}, fmt.Errorf("verify unchanged authentication state: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Plan{}, publicDatabaseError("commit transfer transaction", err)
	}

	plan.Applied = true
	return plan, nil
}

func buildPlan(
	ctx context.Context,
	q queryer,
	sourceID uuid.UUID,
	targetID uuid.UUID,
	lockUsers bool,
) (Plan, error) {
	if err := validateSchema(ctx, q); err != nil {
		return Plan{}, err
	}
	if err := validateUserPair(ctx, q, sourceID, targetID, lockUsers); err != nil {
		return Plan{}, err
	}

	plan := Plan{SchemaVersion: expectedSchemaVersion}
	for _, spec := range transferCountQueries {
		source, err := queryCount(ctx, q, spec.name, spec.query, sourceID.String())
		if err != nil {
			return Plan{}, err
		}
		target, err := queryCount(ctx, q, spec.name, spec.query, targetID.String())
		if err != nil {
			return Plan{}, err
		}
		plan.Transfers = append(plan.Transfers, ResourceCounts{
			Resource: spec.name,
			Source:   source,
			Target:   target,
		})
	}
	for _, spec := range accessCopyCountQueries {
		count, err := queryCount(ctx, q, spec.name, spec.query, sourceID.String())
		if err != nil {
			return Plan{}, err
		}
		plan.AccessCopies = append(plan.AccessCopies, ResourceCount{Resource: spec.name, Count: count})
	}
	for _, spec := range mergeCountQueries {
		count, err := queryCount(
			ctx,
			q,
			spec.name,
			spec.query,
			sourceID.String(),
			targetID.String(),
		)
		if err != nil {
			return Plan{}, err
		}
		plan.Merges = append(plan.Merges, ResourceCount{Resource: spec.name, Count: count})
	}
	for _, spec := range sourceRetainedCountQueries {
		count, err := queryCount(
			ctx,
			q,
			spec.name,
			spec.query,
			sourceID.String(),
			targetID.String(),
		)
		if err != nil {
			return Plan{}, err
		}
		plan.SourceRetained = append(plan.SourceRetained, ResourceCount{Resource: spec.name, Count: count})
	}
	for _, spec := range retainedCountQueries {
		source, err := queryCount(ctx, q, spec.name, spec.query, sourceID.String())
		if err != nil {
			return Plan{}, err
		}
		target, err := queryCount(ctx, q, spec.name, spec.query, targetID.String())
		if err != nil {
			return Plan{}, err
		}
		plan.Retained = append(plan.Retained, ResourceCounts{
			Resource: spec.name,
			Source:   source,
			Target:   target,
		})
	}
	for _, spec := range conflictQueries {
		count, err := queryCount(
			ctx,
			q,
			spec.name,
			spec.query,
			sourceID.String(),
			targetID.String(),
		)
		if err != nil {
			return Plan{}, err
		}
		if count > 0 {
			plan.Conflicts = append(plan.Conflicts, Conflict{Kind: spec.name, Count: count})
		}
	}
	sort.Slice(plan.Conflicts, func(i, j int) bool {
		return plan.Conflicts[i].Kind < plan.Conflicts[j].Kind
	})

	digest, err := planDigest(plan, sourceID, targetID)
	if err != nil {
		return Plan{}, fmt.Errorf("hash transfer plan: %w", err)
	}
	plan.PlanSHA256 = digest
	return plan, nil
}

func validateSchema(ctx context.Context, q queryer) error {
	var version int
	var dirty bool
	if err := q.QueryRowContext(ctx, `SELECT version, dirty FROM schema_migrations LIMIT 1`).Scan(&version, &dirty); err != nil {
		return publicDatabaseError("read schema version", err)
	}
	if version != expectedSchemaVersion || dirty {
		return fmt.Errorf(
			"unsupported Coder schema: require clean version %d",
			expectedSchemaVersion,
		)
	}
	return nil
}

func validateUserPair(
	ctx context.Context,
	q queryer,
	sourceID uuid.UUID,
	targetID uuid.UUID,
	lock bool,
) error {
	if sourceID == uuid.Nil || targetID == uuid.Nil || sourceID == targetID {
		return errors.New("source and target must be distinct non-zero user IDs")
	}

	query := `
		SELECT login_type::text, status::text, deleted, is_system, is_service_account
		FROM users WHERE id = $1
	`
	if lock {
		query += ` FOR UPDATE`
	}

	validate := func(id uuid.UUID, expectedLoginType, label string) error {
		var loginType, status string
		var deleted, system, serviceAccount bool
		err := q.QueryRowContext(ctx, query, id.String()).Scan(
			&loginType,
			&status,
			&deleted,
			&system,
			&serviceAccount,
		)
		if errors.Is(err, sql.ErrNoRows) {
			return fmt.Errorf("%s user does not exist", label)
		}
		if err != nil {
			return publicDatabaseError("read "+label+" user", err)
		}
		if status != "active" || deleted || system || serviceAccount {
			return fmt.Errorf("%s user must be an active human account", label)
		}
		if loginType != expectedLoginType {
			return fmt.Errorf("%s user must use %s authentication", label, expectedLoginType)
		}

		var links, expectedLinks int64
		if err := q.QueryRowContext(ctx, `
			SELECT
				count(*),
				count(*) FILTER (
					WHERE login_type::text = $2 AND linked_id <> ''
				)
			FROM user_links
			WHERE user_id = $1
		`, id.String(), expectedLoginType).Scan(&links, &expectedLinks); err != nil {
			return publicDatabaseError("verify "+label+" identity link", err)
		}
		if links != 1 || expectedLinks != 1 {
			return fmt.Errorf(
				"%s user must have exactly one verified %s identity link and no other identity links",
				label,
				expectedLoginType,
			)
		}
		return nil
	}

	if err := validate(sourceID, "github", "source"); err != nil {
		return err
	}
	return validate(targetID, "oidc", "target")
}

func queryCount(ctx context.Context, q queryer, name, query string, args ...any) (int64, error) {
	var count int64
	if err := q.QueryRowContext(ctx, query, args...).Scan(&count); err != nil {
		return 0, publicDatabaseError("count "+name, err)
	}
	return count, nil
}

func planDigest(plan Plan, sourceID, targetID uuid.UUID) (string, error) {
	payload := struct {
		SourceID       string           `json:"source_user_id"`
		TargetID       string           `json:"target_user_id"`
		SchemaVersion  int              `json:"schema_version"`
		Transfers      []ResourceCounts `json:"transfers"`
		AccessCopies   []ResourceCount  `json:"access_copies"`
		Merges         []ResourceCount  `json:"identical_record_merges"`
		SourceRetained []ResourceCount  `json:"source_retained"`
		Retained       []ResourceCounts `json:"retained"`
		Conflicts      []Conflict       `json:"conflicts"`
	}{
		SourceID:       sourceID.String(),
		TargetID:       targetID.String(),
		SchemaVersion:  plan.SchemaVersion,
		Transfers:      plan.Transfers,
		AccessCopies:   plan.AccessCopies,
		Merges:         plan.Merges,
		SourceRetained: plan.SourceRetained,
		Retained:       plan.Retained,
		Conflicts:      plan.Conflicts,
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}

type transferStep struct {
	name  string
	query string
}

var transferSteps = []transferStep{
	{"copy site roles", `
		UPDATE users AS target_user
		SET rbac_roles = (
			SELECT coalesce(array_agg(role ORDER BY role), '{}'::text[])
			FROM (
				SELECT DISTINCT unnest(target_user.rbac_roles || source_user.rbac_roles) AS role
			) AS roles
		)
		FROM users AS source_user
		WHERE source_user.id = $1 AND target_user.id = $2
	`},
	{"copy organization memberships", `
		INSERT INTO organization_members (user_id, organization_id, created_at, updated_at, roles)
		SELECT $2, organization_id, created_at, updated_at, roles
		FROM organization_members WHERE user_id = $1
		ON CONFLICT (organization_id, user_id) DO UPDATE
		SET roles = (
			SELECT coalesce(array_agg(role ORDER BY role), '{}'::text[])
			FROM (
				SELECT DISTINCT unnest(organization_members.roles || excluded.roles) AS role
			) AS roles
		), updated_at = greatest(organization_members.updated_at, excluded.updated_at)
	`},
	{"copy group memberships", `
		INSERT INTO group_members (user_id, group_id)
		SELECT $2, group_id FROM group_members WHERE user_id = $1
		ON CONFLICT (user_id, group_id) DO NOTHING
	`},
	{"copy template ACL grants", `
		UPDATE templates AS template
		SET user_acl = jsonb_set(
			template.user_acl,
			ARRAY[$2::text],
			(
				SELECT coalesce(jsonb_agg(permission ORDER BY permission::text), '[]'::jsonb)
				FROM (
					SELECT DISTINCT permission
					FROM jsonb_array_elements(
						coalesce(template.user_acl -> $1::text, '[]'::jsonb)
						|| coalesce(template.user_acl -> $2::text, '[]'::jsonb)
					) AS entries(permission)
				) AS permissions
			),
			true
		)
		WHERE template.user_acl ? $1::text
	`},
	{"copy workspace ACL grants", `
		UPDATE workspaces AS workspace
		SET user_acl = jsonb_set(
			workspace.user_acl,
			ARRAY[$2::text],
			coalesce(workspace.user_acl -> $2::text, '{}'::jsonb)
			|| coalesce(workspace.user_acl -> $1::text, '{}'::jsonb)
			|| jsonb_build_object(
				'permissions',
				(
					SELECT coalesce(jsonb_agg(permission ORDER BY permission::text), '[]'::jsonb)
					FROM (
						SELECT DISTINCT permission
						FROM jsonb_array_elements(
							coalesce(workspace.user_acl -> $1::text -> 'permissions', '[]'::jsonb)
							|| coalesce(workspace.user_acl -> $2::text -> 'permissions', '[]'::jsonb)
						) AS entries(permission)
					) AS permissions
				)
			),
			true
		)
		WHERE workspace.user_acl ? $1::text
	`},
	{"copy chat ACL grants", `
		UPDATE chats AS chat
		SET user_acl = jsonb_set(
			chat.user_acl,
			ARRAY[$2::text],
			coalesce(chat.user_acl -> $2::text, '{}'::jsonb)
			|| coalesce(chat.user_acl -> $1::text, '{}'::jsonb)
			|| jsonb_build_object(
				'permissions',
				(
					SELECT coalesce(jsonb_agg(permission ORDER BY permission::text), '[]'::jsonb)
					FROM (
						SELECT DISTINCT permission
						FROM jsonb_array_elements(
							coalesce(chat.user_acl -> $1::text -> 'permissions', '[]'::jsonb)
							|| coalesce(chat.user_acl -> $2::text -> 'permissions', '[]'::jsonb)
						) AS entries(permission)
					) AS permissions
				)
			),
			true
		)
		WHERE chat.user_acl ? $1::text
	`},
	{"move workspaces", `UPDATE workspaces SET owner_id = $2 WHERE owner_id = $1`},
	{"move tasks", `UPDATE tasks SET owner_id = $2 WHERE owner_id = $1`},
	{"move chats", `UPDATE chats SET owner_id = $2 WHERE owner_id = $1`},
	{"move chat messages", `UPDATE chat_messages SET created_by = $2 WHERE created_by = $1`},
	{"move queued chat messages", `UPDATE chat_queued_messages SET created_by = $2 WHERE created_by = $1`},
	{"move chat files", `UPDATE chat_files SET owner_id = $2 WHERE owner_id = $1`},
	{"move files", `UPDATE files SET created_by = $2 WHERE created_by = $1`},
	{"move external auth links", `
		UPDATE external_auth_links AS source
		SET user_id = $2
		WHERE source.user_id = $1
		  AND NOT EXISTS (
			SELECT 1
			FROM external_auth_links AS target
			WHERE target.user_id = $2
			  AND target.provider_id = source.provider_id
		  )
	`},
	{"move MCP server tokens", `UPDATE mcp_server_user_tokens SET user_id = $2 WHERE user_id = $1`},
	{"deduplicate user configs", `
		DELETE FROM user_configs AS source
		USING user_configs AS target
		WHERE source.user_id = $1 AND target.user_id = $2
		  AND source.key = target.key AND source.value = target.value
	`},
	{"move user configs", `UPDATE user_configs SET user_id = $2 WHERE user_id = $1`},
	{"move user secrets", `UPDATE user_secrets SET user_id = $2 WHERE user_id = $1`},
	{"move user skills", `UPDATE user_skills SET user_id = $2 WHERE user_id = $1`},
	{"move AI provider keys", `UPDATE user_ai_provider_keys SET user_id = $2 WHERE user_id = $1`},
	{"deduplicate notification preferences", `
		DELETE FROM notification_preferences AS source
		USING notification_preferences AS target
		WHERE source.user_id = $1 AND target.user_id = $2
		  AND source.notification_template_id = target.notification_template_id
		  AND source.disabled = target.disabled
	`},
	{"move notification preferences", `UPDATE notification_preferences SET user_id = $2 WHERE user_id = $1`},
	{"deduplicate AI budget override", `
		DELETE FROM user_ai_budget_overrides AS source
		USING user_ai_budget_overrides AS target
		WHERE source.user_id = $1 AND target.user_id = $2
		  AND (source.group_id, source.spend_limit_micros)
		      IS NOT DISTINCT FROM (target.group_id, target.spend_limit_micros)
	`},
	{"move AI budget override", `UPDATE user_ai_budget_overrides SET user_id = $2 WHERE user_id = $1`},
	{"merge AI seat state", `
		UPDATE ai_seat_state AS target
		SET first_used_at = least(target.first_used_at, source.first_used_at),
			last_used_at = greatest(target.last_used_at, source.last_used_at),
			last_event_type = CASE
				WHEN source.last_used_at > target.last_used_at THEN source.last_event_type
				ELSE target.last_event_type
			END,
			last_event_description = CASE
				WHEN source.last_used_at > target.last_used_at THEN source.last_event_description
				ELSE target.last_event_description
			END,
			updated_at = greatest(target.updated_at, source.updated_at)
		FROM ai_seat_state AS source
		WHERE source.user_id = $1 AND target.user_id = $2
	`},
	{"remove merged AI seat state", `
		DELETE FROM ai_seat_state AS source
		WHERE source.user_id = $1
		  AND EXISTS (SELECT 1 FROM ai_seat_state AS target WHERE target.user_id = $2)
	`},
	{"move AI seat state", `UPDATE ai_seat_state SET user_id = $2 WHERE user_id = $1`},
}

func executeTransfer(ctx context.Context, tx *sql.Tx, sourceID, targetID uuid.UUID) error {
	for _, step := range transferSteps {
		if _, err := tx.ExecContext(ctx, step.query, sourceID.String(), targetID.String()); err != nil {
			return publicDatabaseError("transfer step "+step.name, err)
		}
	}
	return nil
}

func verifyTransfer(
	ctx context.Context,
	tx *sql.Tx,
	sourceID uuid.UUID,
	targetID uuid.UUID,
	plan Plan,
) error {
	mergeCounts := make(map[string]int64, len(plan.Merges))
	for _, merge := range plan.Merges {
		mergeCounts[merge.Resource] = merge.Count
	}
	sourceRetainedCounts := make(map[string]int64, len(plan.SourceRetained))
	for _, retained := range plan.SourceRetained {
		sourceRetainedCounts[retained.Resource] = retained.Count
	}
	for index, spec := range transferCountQueries {
		sourceCount, err := queryCount(ctx, tx, spec.name, spec.query, sourceID.String())
		if err != nil {
			return err
		}
		expectedSource := sourceRetainedCounts[spec.name]
		if sourceCount != expectedSource {
			return fmt.Errorf("verify transfer: source has an unexpected number of %s records", spec.name)
		}
		targetCount, err := queryCount(ctx, tx, spec.name, spec.query, targetID.String())
		if err != nil {
			return err
		}
		expectedTarget := plan.Transfers[index].Source + plan.Transfers[index].Target -
			mergeCounts[spec.name] - expectedSource
		if targetCount != expectedTarget {
			return fmt.Errorf("verify transfer: target has an unexpected number of %s records", spec.name)
		}
	}
	for index, spec := range retainedCountQueries {
		sourceCount, err := queryCount(ctx, tx, spec.name, spec.query, sourceID.String())
		if err != nil {
			return err
		}
		targetCount, err := queryCount(ctx, tx, spec.name, spec.query, targetID.String())
		if err != nil {
			return err
		}
		if sourceCount != plan.Retained[index].Source || targetCount != plan.Retained[index].Target {
			return fmt.Errorf("verify transfer: retained %s records changed", spec.name)
		}
	}

	postconditionQueries := []namedQuery{
		{"site roles", `
			SELECT count(*) FROM users AS source, users AS target
			WHERE source.id = $1 AND target.id = $2
			  AND NOT (target.rbac_roles @> source.rbac_roles)
		`},
		{"organization memberships", `
			SELECT count(*)
			FROM organization_members AS source
			LEFT JOIN organization_members AS target
			  ON target.user_id = $2 AND target.organization_id = source.organization_id
			WHERE source.user_id = $1
			  AND (target.user_id IS NULL OR NOT (target.roles @> source.roles))
		`},
		{"group memberships", `
			SELECT count(*)
			FROM group_members AS source
			LEFT JOIN group_members AS target
			  ON target.user_id = $2 AND target.group_id = source.group_id
			WHERE source.user_id = $1 AND target.user_id IS NULL
		`},
		{"template ACL grants", `
			SELECT count(*) FROM templates
			WHERE user_acl ? $1::text
			  AND NOT (coalesce(user_acl -> $2::text, '[]'::jsonb) @> (user_acl -> $1::text))
		`},
		{"workspace ACL grants", `
			SELECT count(*) FROM workspaces
			WHERE user_acl ? $1::text
			  AND NOT (
				coalesce(user_acl -> $2::text -> 'permissions', '[]'::jsonb)
				@> coalesce(user_acl -> $1::text -> 'permissions', '[]'::jsonb)
			  )
		`},
		{"chat ACL grants", `
			SELECT count(*) FROM chats
			WHERE user_acl ? $1::text
			  AND NOT (
				coalesce(user_acl -> $2::text -> 'permissions', '[]'::jsonb)
				@> coalesce(user_acl -> $1::text -> 'permissions', '[]'::jsonb)
			  )
		`},
	}
	for _, spec := range postconditionQueries {
		count, err := queryCount(
			ctx,
			tx,
			spec.name,
			spec.query,
			sourceID.String(),
			targetID.String(),
		)
		if err != nil {
			return err
		}
		if count != 0 {
			return fmt.Errorf("verify transfer: incomplete %s", spec.name)
		}
	}
	return nil
}

func publicDatabaseError(operation string, err error) error {
	var pqErr *pq.Error
	if errors.As(err, &pqErr) {
		return fmt.Errorf("%s failed (SQLSTATE %s)", operation, string(pqErr.Code))
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return fmt.Errorf("%s failed: operation canceled", operation)
	}
	return fmt.Errorf("%s failed", operation)
}
