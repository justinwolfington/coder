# Coder user migration

This internal command moves durable user-owned data from an existing GitHub
Coder user to an existing OIDC Coder user. It is pinned to the schema shipped
with Coder v2.35.4.

It can also prepare a GitHub-authenticated user for an administrative OIDC
migration when no OIDC Coder user exists. This operation changes that user's
email and login type in place. It retains the GitHub identity link, API keys,
workspaces, and all other user data. On the next Okta login, Coder finds the
pre-provisioned user by the new email and binds the verified OIDC subject.

The data-transfer operation does not change login types, identity links, API
keys, sessions, Git SSH keys, web push subscriptions, historical notifications,
audit records, or either user record. Account retirement is a separate
operation.

The source must be an active human user with one GitHub identity link. The
target must be an active human user with one OIDC identity link. Neither user
may have an additional identity link.

The transaction moves workspaces, tasks, chats and their user attribution,
uploaded files, non-colliding external-auth and MCP connections, user
configuration, secrets, skills, AI provider keys and state, and notification
preferences. It copies site roles, organization and group memberships, and ACL
grants to the target while retaining source access. External-auth links for a
provider already linked to the target remain on both users so neither
credential is overwritten. Identical records with unique keys are merged;
other incompatible records stop the transfer before any write.

Run `plan` first:

```sh
export CODER_PG_CONNECTION_URL='postgres://...'
export CODER_TRANSFER_SOURCE_USER_ID="$GITHUB_CODER_USER_ID"
export CODER_TRANSFER_TARGET_USER_ID="$OKTA_CODER_USER_ID"
coder-user-data-transfer plan
```

The plan contains only resource counts, identical-record merge counts,
conflict categories, and a SHA-256 digest. It does not print account
identifiers or stored values. An apply must provide the exact digest from a
current, conflict-free plan:

```sh
export CODER_TRANSFER_PLAN_SHA256="$PLAN_SHA256"
coder-user-data-transfer apply
```

Apply uses a serializable PostgreSQL transaction and locks both user rows. Any
validation failure, conflict, concurrent write, or transfer error rolls the
entire operation back.

For an in-place login migration, the user must be an active human account with
GitHub authentication, exactly one verified GitHub identity link, and no OIDC
identity link. The target email must use the `abridge.com` domain and must not
belong to another active Coder user. Workspaces do not need to be stopped
because their owner does not change.

```sh
export CODER_TRANSFER_SOURCE_USER_ID="$GITHUB_CODER_USER_ID"
export CODER_LOGIN_TARGET_EMAIL="$OKTA_EMAIL"
coder-user-data-transfer login-plan

export CODER_TRANSFER_PLAN_SHA256="$PLAN_SHA256"
coder-user-data-transfer login-apply
```

The login migration retains the existing GitHub identity link so that the
change is recoverable before the first Okta login. The user's OIDC link is
created only after Okta proves control of the configured email. GitHub login is
rejected after the login type changes, even while the retained link exists.

Run the integration test against an exact v2.35.4 source checkout:

```sh
./docker/coder-user-data-transfer/test-integration.sh /path/to/coder-v2.35.4
```

The test verifies the schema dump hash before creating an ephemeral,
loopback-only PostgreSQL container. It covers a successful transfer, conflict
refusal, authentication-state preservation, and transaction rollback.
