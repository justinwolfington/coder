package database

// Constraint names raised by the user soft-delete guard and per-user cap
// trigger functions installed by migration 000587 (fail_if_user_deleted,
// require_read_committed, and the cap functions they serve). These are
// raised with USING CONSTRAINT from plpgsql, not declared as table CHECK
// constraints, so dbgen does not emit them in check_constraint.go; they are
// declared once here so handlers and tests share one set of literals.
// TestSoftDeleteGuardConstraintNames pins each name against the live
// trigger function definitions.
const (
	// Raised by fail_if_user_deleted when inserting (or, for the upsert
	// tables, updating) a child row for a soft-deleted user.
	//nolint:gosec // A trigger constraint name, not a credential.
	CheckAPIKeyUserDeleted               CheckConstraint = "api_key_user_deleted"
	CheckUserLinkUserDeleted             CheckConstraint = "user_link_user_deleted"
	CheckUserSecretUserDeleted           CheckConstraint = "user_secret_user_deleted"
	CheckUserSkillUserDeleted            CheckConstraint = "user_skill_user_deleted"
	CheckUserAIProviderKeyUserDeleted    CheckConstraint = "user_ai_provider_key_user_deleted"
	CheckOrganizationMemberUserDeleted   CheckConstraint = "organization_member_user_deleted"
	CheckUserAIBudgetOverrideUserDeleted CheckConstraint = "user_ai_budget_override_user_deleted"

	// Raised by require_read_committed when a per-user cap trigger runs
	// under an isolation level whose snapshot could overshoot the cap.
	CheckUserSecretsCapIsolation CheckConstraint = "user_secrets_cap_isolation"
	CheckUserSkillsCapIsolation  CheckConstraint = "user_skills_cap_isolation"
)
