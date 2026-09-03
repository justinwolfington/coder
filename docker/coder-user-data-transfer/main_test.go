package main

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lib/pq"
)

func TestParseCommand(t *testing.T) {
	t.Parallel()

	sourceID := uuid.New()
	targetID := uuid.New()
	validSHA := strings.Repeat("a", 64)

	tests := []struct {
		name    string
		args    []string
		wantErr string
	}{
		{name: "missing command", wantErr: "command must be plan, apply, login-plan, or login-apply"},
		{name: "unknown command", args: []string{"delete"}, wantErr: "command must be plan, apply, login-plan, or login-apply"},
		{name: "missing source", args: []string{"plan", "--target-user-id", targetID.String()}, wantErr: "source-user-id must be a non-zero UUID"},
		{name: "missing target", args: []string{"plan", "--source-user-id", sourceID.String()}, wantErr: "target-user-id must be a non-zero UUID"},
		{name: "same user", args: []string{"plan", "--source-user-id", sourceID.String(), "--target-user-id", sourceID.String()}, wantErr: "source and target users must differ"},
		{name: "plan with SHA", args: []string{"plan", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "--plan-sha256", validSHA}, wantErr: "plan-sha256 is only valid with apply"},
		{name: "apply without SHA", args: []string{"apply", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String()}, wantErr: "apply requires a 64-character plan-sha256"},
		{name: "short SHA", args: []string{"apply", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "--plan-sha256", "abc"}, wantErr: "apply requires a 64-character plan-sha256"},
		{name: "uppercase SHA", args: []string{"apply", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "--plan-sha256", strings.Repeat("A", 64)}, wantErr: "plan-sha256 must be lowercase hexadecimal"},
		{name: "nonhex SHA", args: []string{"apply", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "--plan-sha256", strings.Repeat("z", 64)}, wantErr: "plan-sha256 must be lowercase hexadecimal"},
		{name: "unexpected argument", args: []string{"plan", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "extra"}, wantErr: "unexpected positional arguments"},
		{name: "valid plan", args: []string{"plan", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String()}},
		{name: "valid apply", args: []string{"apply", "--source-user-id", sourceID.String(), "--target-user-id", targetID.String(), "--plan-sha256", validSHA}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			options, err := parseCommand(test.args, func(string) string { return "" }, &strings.Builder{})
			if test.wantErr != "" {
				if err == nil || err.Error() != test.wantErr {
					t.Fatalf("parseCommand() error = %v, want %q", err, test.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseCommand() unexpected error: %v", err)
			}
			if options.mode != test.args[0] {
				t.Fatalf("parseCommand() mode = %q, want %q", options.mode, test.args[0])
			}
			if options.sourceID != sourceID || options.targetID != targetID {
				t.Fatal("parseCommand() changed a user ID")
			}
		})
	}
}

func TestParseLoginCommand(t *testing.T) {
	t.Parallel()

	sourceID := uuid.New()
	validSHA := strings.Repeat("c", 64)
	tests := []struct {
		name      string
		args      []string
		wantMode  string
		wantEmail string
		wantErr   string
	}{
		{
			name:    "missing email",
			args:    []string{"login-plan", "--source-user-id", sourceID.String()},
			wantErr: "target-email must be a plain email address",
		},
		{
			name: "external email",
			args: []string{
				"login-plan", "--source-user-id", sourceID.String(),
				"--target-email", "user@example.com",
			},
			wantErr: "target-email must use the abridge.com domain",
		},
		{
			name: "target user ID",
			args: []string{
				"login-plan", "--source-user-id", sourceID.String(),
				"--target-email", "user@abridge.com", "--target-user-id", uuid.NewString(),
			},
			wantErr: "target-user-id is only valid for data transfer",
		},
		{
			name: "apply without digest",
			args: []string{
				"login-apply", "--source-user-id", sourceID.String(),
				"--target-email", "user@abridge.com",
			},
			wantErr: "apply requires a 64-character plan-sha256",
		},
		{
			name: "valid plan",
			args: []string{
				"login-plan", "--source-user-id", sourceID.String(),
				"--target-email", "User@Abridge.com",
			},
			wantMode:  "plan",
			wantEmail: "user@abridge.com",
		},
		{
			name: "valid apply",
			args: []string{
				"login-apply", "--source-user-id", sourceID.String(),
				"--target-email", "user@abridge.com", "--plan-sha256", validSHA,
			},
			wantMode:  "apply",
			wantEmail: "user@abridge.com",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			options, err := parseCommand(test.args, func(string) string { return "" }, &strings.Builder{})
			if test.wantErr != "" {
				if err == nil || err.Error() != test.wantErr {
					t.Fatalf("parseCommand() error = %v, want %q", err, test.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseCommand() unexpected error: %v", err)
			}
			if options.operation != operationLogin || options.mode != test.wantMode {
				t.Fatalf("parseCommand() operation/mode = %q/%q", options.operation, options.mode)
			}
			if options.sourceID != sourceID || options.targetID != uuid.Nil {
				t.Fatal("parseCommand() changed a user ID")
			}
			if options.targetEmail != test.wantEmail {
				t.Fatalf("parseCommand() target email = %q, want %q", options.targetEmail, test.wantEmail)
			}
		})
	}
}

func TestParseCommandFromEnvironment(t *testing.T) {
	t.Parallel()

	sourceID := uuid.New()
	targetID := uuid.New()
	validSHA := strings.Repeat("b", 64)
	values := map[string]string{
		sourceIDEnv: sourceID.String(),
		targetIDEnv: targetID.String(),
		planSHAEnv:  validSHA,
	}
	getenv := func(key string) string { return values[key] }

	options, err := parseCommand([]string{"apply"}, getenv, &strings.Builder{})
	if err != nil {
		t.Fatalf("parseCommand() error: %v", err)
	}
	if options.sourceID != sourceID || options.targetID != targetID {
		t.Fatal("parseCommand() did not read user IDs from the environment")
	}
	if options.planSHA256 != validSHA {
		t.Fatal("parseCommand() did not read the plan digest from the environment")
	}
}

func TestParseLoginCommandFromEnvironment(t *testing.T) {
	t.Parallel()

	sourceID := uuid.New()
	validSHA := strings.Repeat("d", 64)
	values := map[string]string{
		sourceIDEnv:    sourceID.String(),
		targetEmailEnv: "user@abridge.com",
		planSHAEnv:     validSHA,
	}
	getenv := func(key string) string { return values[key] }

	options, err := parseCommand([]string{"login-apply"}, getenv, &strings.Builder{})
	if err != nil {
		t.Fatalf("parseCommand() error: %v", err)
	}
	if options.sourceID != sourceID || options.targetEmail != "user@abridge.com" {
		t.Fatal("parseCommand() did not read login migration inputs from the environment")
	}
	if options.planSHA256 != validSHA {
		t.Fatal("parseCommand() did not read the plan digest from the environment")
	}
}

func TestPlanDigestBindsUserPair(t *testing.T) {
	t.Parallel()

	plan := Plan{
		SchemaVersion: expectedSchemaVersion,
		Transfers: []ResourceCounts{
			{Resource: "workspaces", Source: 2, Target: 1},
		},
	}
	sourceID := uuid.New()
	targetID := uuid.New()

	digest, err := planDigest(plan, sourceID, targetID)
	if err != nil {
		t.Fatalf("planDigest() error: %v", err)
	}
	repeated, err := planDigest(plan, sourceID, targetID)
	if err != nil {
		t.Fatalf("planDigest() repeated error: %v", err)
	}
	if digest != repeated {
		t.Fatal("planDigest() is not deterministic")
	}
	if len(digest) != 64 {
		t.Fatalf("planDigest() length = %d, want 64", len(digest))
	}

	otherDigest, err := planDigest(plan, uuid.New(), targetID)
	if err != nil {
		t.Fatalf("planDigest() other pair error: %v", err)
	}
	if digest == otherDigest {
		t.Fatal("planDigest() did not bind the source user")
	}
}

func TestLoginMigrationPlanDigestBindsAuthenticationState(t *testing.T) {
	t.Parallel()

	plan := LoginMigrationPlan{SchemaVersion: expectedSchemaVersion}
	userID := uuid.New()
	state := loginMigrationState{
		Email:          "user@example.invalid",
		LoginType:      "github",
		Status:         "active",
		UpdatedAt:      time.Unix(1_700_000_000, 0).UTC(),
		GitHubLinks:    1,
		GitHubLinkedID: "github-subject",
	}
	digest, err := loginMigrationPlanDigest(plan, userID, "user@abridge.com", state)
	if err != nil {
		t.Fatalf("loginMigrationPlanDigest() error: %v", err)
	}
	repeated, err := loginMigrationPlanDigest(plan, userID, "user@abridge.com", state)
	if err != nil {
		t.Fatalf("loginMigrationPlanDigest() repeated error: %v", err)
	}
	if digest != repeated || len(digest) != 64 {
		t.Fatal("loginMigrationPlanDigest() is not deterministic")
	}

	changedState := state
	changedState.GitHubLinkedID = "different-subject"
	for name, otherDigest := range map[string]string{
		"user":  mustLoginMigrationDigest(t, plan, uuid.New(), "user@abridge.com", state),
		"email": mustLoginMigrationDigest(t, plan, userID, "other@abridge.com", state),
		"state": mustLoginMigrationDigest(t, plan, userID, "user@abridge.com", changedState),
	} {
		if digest == otherDigest {
			t.Fatalf("loginMigrationPlanDigest() did not bind %s", name)
		}
	}
}

func mustLoginMigrationDigest(
	t *testing.T,
	plan LoginMigrationPlan,
	userID uuid.UUID,
	targetEmail string,
	state loginMigrationState,
) string {
	t.Helper()
	digest, err := loginMigrationPlanDigest(plan, userID, targetEmail, state)
	if err != nil {
		t.Fatalf("loginMigrationPlanDigest() error: %v", err)
	}
	return digest
}

func TestPlanJSONOmitsUserIDs(t *testing.T) {
	t.Parallel()

	sourceID := uuid.New()
	targetID := uuid.New()
	plan := Plan{
		SchemaVersion: expectedSchemaVersion,
		Transfers: []ResourceCounts{
			{Resource: "workspaces", Source: 1},
		},
		PlanSHA256: strings.Repeat("0", 64),
	}

	encoded, err := json.Marshal(plan)
	if err != nil {
		t.Fatalf("json.Marshal() error: %v", err)
	}
	output := string(encoded)
	for _, disallowed := range []string{
		sourceID.String(),
		targetID.String(),
		"source_user_id",
		"target_user_id",
	} {
		if strings.Contains(output, disallowed) {
			t.Fatalf("plan output contains %q", disallowed)
		}
	}
}

func TestLoginMigrationPlanJSONOmitsIdentifiers(t *testing.T) {
	t.Parallel()

	userID := uuid.New()
	plan := LoginMigrationPlan{
		SchemaVersion: expectedSchemaVersion,
		Updates:       []string{"email", "login_type"},
		PlanSHA256:    strings.Repeat("0", 64),
	}

	encoded, err := json.Marshal(plan)
	if err != nil {
		t.Fatalf("json.Marshal() error: %v", err)
	}
	output := string(encoded)
	for _, disallowed := range []string{
		userID.String(),
		"user@abridge.com",
		"user_id",
		"target_email",
	} {
		if strings.Contains(output, disallowed) {
			t.Fatalf("login migration plan output contains %q", disallowed)
		}
	}
}

func TestPublicDatabaseError(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		err        error
		want       string
		disallowed string
	}{
		{
			name: "PostgreSQL error",
			err: &pq.Error{
				Code:    pq.ErrorCode("23505"),
				Message: "duplicate key contains account identifier",
				Detail:  "secret detail",
			},
			want:       "transfer failed (SQLSTATE 23505)",
			disallowed: "account identifier",
		},
		{
			name:       "generic error",
			err:        errors.New("postgres://user:password@example.invalid/database"),
			want:       "transfer failed",
			disallowed: "password",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			got := publicDatabaseError("transfer", test.err).Error()
			if got != test.want {
				t.Fatalf("publicDatabaseError() = %q, want %q", got, test.want)
			}
			if strings.Contains(got, test.disallowed) {
				t.Fatalf("publicDatabaseError() exposed %q", test.disallowed)
			}
		})
	}
}
