package dbauthz

import (
	"context"
	"encoding/json"

	"golang.org/x/xerrors"

	"github.com/coder/coder/v2/coderd/database"
	"github.com/coder/coder/v2/coderd/rbac"
	"github.com/coder/coder/v2/coderd/rbac/policy"
)

// The session count read queries take the app family attribution registry as
// a single jsonb parameter. An empty registry is not a valid input: the
// queries would run and return zero counts without error, silently dropping
// every family's sessions from deployment stats, insights, Prometheus, and
// telemetry. dbauthz wraps every production store, including the transaction
// stores used by the rollup, so validating here makes a forgotten registry
// fail the call loudly instead of failing the data quietly. These methods
// override the generated ones in dbauthz.go; scripts/dbgen preserves methods
// defined outside that file.

func validateSessionCountAppFamilies(appFamilies json.RawMessage) error {
	if len(appFamilies) == 0 {
		return xerrors.Errorf("developer error: session count app families must not be empty, populate them with codersdk.SessionCountAppFamiliesJSON()")
	}
	return nil
}

func (q *querier) GetDeploymentWorkspaceAgentStats(ctx context.Context, arg database.GetDeploymentWorkspaceAgentStatsParams) (database.GetDeploymentWorkspaceAgentStatsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return database.GetDeploymentWorkspaceAgentStatsRow{}, err
	}
	return q.db.GetDeploymentWorkspaceAgentStats(ctx, arg)
}

func (q *querier) GetDeploymentWorkspaceAgentUsageStats(ctx context.Context, arg database.GetDeploymentWorkspaceAgentUsageStatsParams) (database.GetDeploymentWorkspaceAgentUsageStatsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return database.GetDeploymentWorkspaceAgentUsageStatsRow{}, err
	}
	return q.db.GetDeploymentWorkspaceAgentUsageStats(ctx, arg)
}

func (q *querier) GetWorkspaceAgentStats(ctx context.Context, arg database.GetWorkspaceAgentStatsParams) ([]database.GetWorkspaceAgentStatsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return nil, err
	}
	return q.db.GetWorkspaceAgentStats(ctx, arg)
}

func (q *querier) GetWorkspaceAgentStatsAndLabels(ctx context.Context, arg database.GetWorkspaceAgentStatsAndLabelsParams) ([]database.GetWorkspaceAgentStatsAndLabelsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return nil, err
	}
	return q.db.GetWorkspaceAgentStatsAndLabels(ctx, arg)
}

func (q *querier) GetWorkspaceAgentUsageStats(ctx context.Context, arg database.GetWorkspaceAgentUsageStatsParams) ([]database.GetWorkspaceAgentUsageStatsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return nil, err
	}
	return q.db.GetWorkspaceAgentUsageStats(ctx, arg)
}

func (q *querier) GetWorkspaceAgentUsageStatsAndLabels(ctx context.Context, arg database.GetWorkspaceAgentUsageStatsAndLabelsParams) ([]database.GetWorkspaceAgentUsageStatsAndLabelsRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return nil, err
	}
	return q.db.GetWorkspaceAgentUsageStatsAndLabels(ctx, arg)
}

func (q *querier) GetTemplateInsightsByTemplate(ctx context.Context, arg database.GetTemplateInsightsByTemplateParams) ([]database.GetTemplateInsightsByTemplateRow, error) {
	if err := validateSessionCountAppFamilies(arg.AppFamilies); err != nil {
		return nil, err
	}
	// Only used by prometheus metrics collector. No need to check update template perms.
	if err := q.authorizeContext(ctx, policy.ActionViewInsights, rbac.ResourceTemplate); err != nil {
		return nil, err
	}
	return q.db.GetTemplateInsightsByTemplate(ctx, arg)
}

func (q *querier) UpsertTemplateUsageStats(ctx context.Context, appFamilies json.RawMessage) error {
	if err := validateSessionCountAppFamilies(appFamilies); err != nil {
		return err
	}
	if err := q.authorizeContext(ctx, policy.ActionUpdate, rbac.ResourceSystem); err != nil {
		return err
	}
	return q.db.UpsertTemplateUsageStats(ctx, appFamilies)
}
