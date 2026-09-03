package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

const corporateEmailDomain = "abridge.com"

type LoginMigrationPlan struct {
	SchemaVersion int             `json:"schema_version"`
	Updates       []string        `json:"updates"`
	Retained      []ResourceCount `json:"retained"`
	Conflicts     []Conflict      `json:"conflicts"`
	PlanSHA256    string          `json:"plan_sha256"`
	Applied       bool            `json:"applied"`
}

type loginMigrationState struct {
	Email          string
	LoginType      string
	Status         string
	Deleted        bool
	System         bool
	ServiceAccount bool
	UpdatedAt      time.Time
	GitHubLinks    int64
	OIDCLinks      int64
	OtherLinks     int64
	GitHubLinkedID string
}

var loginMigrationRetainedCountQueries = []namedQuery{
	{"workspaces", `SELECT count(*) FROM workspaces WHERE owner_id = $1`},
	{"api_keys", `SELECT count(*) FROM api_keys WHERE user_id = $1`},
	{"github_identity_links", `SELECT count(*) FROM user_links WHERE user_id = $1 AND login_type = 'github'`},
	{"oidc_identity_links", `SELECT count(*) FROM user_links WHERE user_id = $1 AND login_type = 'oidc'`},
	{"external_auth_links", `SELECT count(*) FROM external_auth_links WHERE user_id = $1`},
	{"git_ssh_keys", `SELECT count(*) FROM gitsshkeys WHERE user_id = $1`},
}

func normalizeTargetEmail(raw string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	local, domain, ok := strings.Cut(normalized, "@")
	if !ok || local == "" || strings.Contains(domain, "@") ||
		len(local) > 64 || len(normalized) > 254 || strings.HasPrefix(local, ".") ||
		strings.HasSuffix(local, ".") || strings.Contains(local, "..") {
		return "", errors.New("target-email must be a plain email address")
	}
	for _, char := range local {
		if (char < 'a' || char > 'z') && (char < '0' || char > '9') &&
			!strings.ContainsRune("._+-", char) {
			return "", errors.New("target-email must be a plain email address")
		}
	}
	if domain != corporateEmailDomain {
		return "", fmt.Errorf("target-email must use the %s domain", corporateEmailDomain)
	}
	return normalized, nil
}

func CreateLoginMigrationPlan(
	ctx context.Context,
	db *sql.DB,
	userID uuid.UUID,
	targetEmail string,
) (LoginMigrationPlan, error) {
	targetEmail, err := normalizeTargetEmail(targetEmail)
	if err != nil {
		return LoginMigrationPlan{}, err
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{
		Isolation: sql.LevelRepeatableRead,
		ReadOnly:  true,
	})
	if err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("start login migration plan transaction", err)
	}
	defer tx.Rollback()

	plan, _, err := buildLoginMigrationPlan(ctx, tx, userID, targetEmail, false)
	if err != nil {
		return LoginMigrationPlan{}, err
	}
	if err := tx.Commit(); err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("commit login migration plan transaction", err)
	}
	return plan, nil
}

func ApplyLoginMigration(
	ctx context.Context,
	db *sql.DB,
	userID uuid.UUID,
	targetEmail string,
	expectedPlanSHA256 string,
) (LoginMigrationPlan, error) {
	targetEmail, err := normalizeTargetEmail(targetEmail)
	if err != nil {
		return LoginMigrationPlan{}, err
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("start login migration transaction", err)
	}
	defer tx.Rollback()

	for _, statement := range []string{
		`SET LOCAL lock_timeout = '10s'`,
		`SET LOCAL statement_timeout = '90s'`,
	} {
		if _, err := tx.ExecContext(ctx, statement); err != nil {
			return LoginMigrationPlan{}, publicDatabaseError("configure login migration transaction", err)
		}
	}
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock($1)`, transferAdvisoryLock); err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("lock login migration operation", err)
	}

	plan, state, err := buildLoginMigrationPlan(ctx, tx, userID, targetEmail, true)
	if err != nil {
		return LoginMigrationPlan{}, err
	}
	if plan.PlanSHA256 != expectedPlanSHA256 {
		return LoginMigrationPlan{}, errors.New("plan-sha256 does not match the current database state")
	}
	if len(plan.Conflicts) != 0 {
		return LoginMigrationPlan{}, errors.New("login migration plan contains conflicts")
	}

	result, err := tx.ExecContext(ctx, `
		UPDATE users
		SET email = $2,
			login_type = 'oidc',
			hashed_password = ''::bytea,
			updated_at = CURRENT_TIMESTAMP
		WHERE id = $1 AND email = $3 AND login_type = 'github'
			AND status = 'active' AND deleted = false
			AND is_system = false AND is_service_account = false
	`, userID.String(), targetEmail, state.Email)
	if err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("update user login", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("read updated user count", err)
	}
	if rows != 1 {
		return LoginMigrationPlan{}, errors.New("update user login affected an unexpected number of users")
	}

	if err := verifyLoginMigration(ctx, tx, userID, targetEmail, state, plan); err != nil {
		return LoginMigrationPlan{}, err
	}
	if err := tx.Commit(); err != nil {
		return LoginMigrationPlan{}, publicDatabaseError("commit login migration transaction", err)
	}

	plan.Applied = true
	return plan, nil
}

func buildLoginMigrationPlan(
	ctx context.Context,
	q queryer,
	userID uuid.UUID,
	targetEmail string,
	lockUser bool,
) (LoginMigrationPlan, loginMigrationState, error) {
	if err := validateSchema(ctx, q); err != nil {
		return LoginMigrationPlan{}, loginMigrationState{}, err
	}
	state, err := readLoginMigrationState(ctx, q, userID, lockUser)
	if err != nil {
		return LoginMigrationPlan{}, loginMigrationState{}, err
	}
	if err := validateLoginMigrationState(state); err != nil {
		return LoginMigrationPlan{}, loginMigrationState{}, err
	}

	plan := LoginMigrationPlan{
		SchemaVersion: expectedSchemaVersion,
		Updates:       []string{"email", "login_type"},
	}
	for _, spec := range loginMigrationRetainedCountQueries {
		count, err := queryCount(ctx, q, spec.name, spec.query, userID.String())
		if err != nil {
			return LoginMigrationPlan{}, loginMigrationState{}, err
		}
		plan.Retained = append(plan.Retained, ResourceCount{Resource: spec.name, Count: count})
	}

	targetMatches, err := queryCount(ctx, q, "target email", `
		SELECT count(*)
		FROM users
		WHERE lower(email) = lower($1) AND id <> $2 AND deleted = false
	`, targetEmail, userID.String())
	if err != nil {
		return LoginMigrationPlan{}, loginMigrationState{}, err
	}
	if targetMatches > 0 {
		plan.Conflicts = append(plan.Conflicts, Conflict{Kind: "target_email_in_use", Count: targetMatches})
	}

	digest, err := loginMigrationPlanDigest(plan, userID, targetEmail, state)
	if err != nil {
		return LoginMigrationPlan{}, loginMigrationState{}, fmt.Errorf("hash login migration plan: %w", err)
	}
	plan.PlanSHA256 = digest
	return plan, state, nil
}

func readLoginMigrationState(
	ctx context.Context,
	q queryer,
	userID uuid.UUID,
	lock bool,
) (loginMigrationState, error) {
	query := `
		SELECT email, login_type::text, status::text, deleted, is_system,
			is_service_account, updated_at
		FROM users
		WHERE id = $1
	`
	if lock {
		query += ` FOR UPDATE`
	}

	var state loginMigrationState
	err := q.QueryRowContext(ctx, query, userID.String()).Scan(
		&state.Email,
		&state.LoginType,
		&state.Status,
		&state.Deleted,
		&state.System,
		&state.ServiceAccount,
		&state.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return loginMigrationState{}, errors.New("login migration user does not exist")
	}
	if err != nil {
		return loginMigrationState{}, publicDatabaseError("read login migration user", err)
	}

	if err := q.QueryRowContext(ctx, `
		SELECT
			count(*) FILTER (WHERE login_type = 'github'),
			count(*) FILTER (WHERE login_type = 'oidc'),
			count(*) FILTER (WHERE login_type NOT IN ('github', 'oidc')),
			coalesce(min(linked_id) FILTER (WHERE login_type = 'github'), '')
		FROM user_links
		WHERE user_id = $1
	`, userID.String()).Scan(
		&state.GitHubLinks,
		&state.OIDCLinks,
		&state.OtherLinks,
		&state.GitHubLinkedID,
	); err != nil {
		return loginMigrationState{}, publicDatabaseError("read login migration identity links", err)
	}
	return state, nil
}

func validateLoginMigrationState(state loginMigrationState) error {
	if state.Status != "active" || state.Deleted || state.System || state.ServiceAccount {
		return errors.New("login migration user must be an active human account")
	}
	if state.LoginType != "github" {
		return errors.New("login migration user must use github authentication")
	}
	if state.GitHubLinks != 1 || state.GitHubLinkedID == "" || state.OIDCLinks != 0 || state.OtherLinks != 0 {
		return errors.New("login migration user must have exactly one verified github identity link and no other identity links")
	}
	return nil
}

func loginMigrationPlanDigest(
	plan LoginMigrationPlan,
	userID uuid.UUID,
	targetEmail string,
	state loginMigrationState,
) (string, error) {
	payload := struct {
		UserID         string     `json:"user_id"`
		TargetEmail    string     `json:"target_email"`
		SchemaVersion  int        `json:"schema_version"`
		CurrentEmail   string     `json:"current_email"`
		LoginType      string     `json:"login_type"`
		Status         string     `json:"status"`
		Deleted        bool       `json:"deleted"`
		System         bool       `json:"system"`
		ServiceAccount bool       `json:"service_account"`
		UpdatedAt      time.Time  `json:"updated_at"`
		GitHubLinks    int64      `json:"github_links"`
		OIDCLinks      int64      `json:"oidc_links"`
		OtherLinks     int64      `json:"other_links"`
		GitHubLinkedID string     `json:"github_linked_id"`
		Conflicts      []Conflict `json:"conflicts"`
	}{
		UserID:         userID.String(),
		TargetEmail:    targetEmail,
		SchemaVersion:  plan.SchemaVersion,
		CurrentEmail:   state.Email,
		LoginType:      state.LoginType,
		Status:         state.Status,
		Deleted:        state.Deleted,
		System:         state.System,
		ServiceAccount: state.ServiceAccount,
		UpdatedAt:      state.UpdatedAt,
		GitHubLinks:    state.GitHubLinks,
		OIDCLinks:      state.OIDCLinks,
		OtherLinks:     state.OtherLinks,
		GitHubLinkedID: state.GitHubLinkedID,
		Conflicts:      plan.Conflicts,
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:]), nil
}

func verifyLoginMigration(
	ctx context.Context,
	tx *sql.Tx,
	userID uuid.UUID,
	targetEmail string,
	before loginMigrationState,
	plan LoginMigrationPlan,
) error {
	var email, loginType, status string
	var deleted, system, serviceAccount, passwordCleared bool
	if err := tx.QueryRowContext(ctx, `
		SELECT email, login_type::text, status::text, deleted, is_system,
			is_service_account, octet_length(hashed_password) = 0
		FROM users
		WHERE id = $1
	`, userID.String()).Scan(
		&email,
		&loginType,
		&status,
		&deleted,
		&system,
		&serviceAccount,
		&passwordCleared,
	); err != nil {
		return publicDatabaseError("verify migrated user", err)
	}
	if email != targetEmail || loginType != "oidc" || status != before.Status ||
		deleted != before.Deleted || system != before.System ||
		serviceAccount != before.ServiceAccount || !passwordCleared {
		return errors.New("verify login migration: user state is unexpected")
	}

	for index, spec := range loginMigrationRetainedCountQueries {
		count, err := queryCount(ctx, tx, spec.name, spec.query, userID.String())
		if err != nil {
			return err
		}
		if count != plan.Retained[index].Count {
			return fmt.Errorf("verify login migration: retained %s records changed", spec.name)
		}
	}
	linkedIDMatches, err := queryCount(ctx, tx, "github linked ID", `
		SELECT count(*)
		FROM user_links
		WHERE user_id = $1 AND login_type = 'github' AND linked_id = $2
	`, userID.String(), before.GitHubLinkedID)
	if err != nil {
		return err
	}
	if linkedIDMatches != 1 {
		return errors.New("verify login migration: github identity link changed")
	}
	return nil
}
