#!/bin/bash

# This script creates a machine user and generates a long-lived token for Coder
# Usage: ./create_coder_tokens.sh <CODER_URL>
# Example: ./create_coder_tokens.sh https://coder.abridge.coffee/

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <CODER_URL>" >&2
  exit 1
fi

CODER_URL=$1
USERNAME="gh-coder"
EMAIL="gh-coder@abridge-artifact-registry.iam.gserviceaccount.com"
TOKEN_LIFETIME="8760h"

echo "Logging into $CODER_URL"

coder login "$CODER_URL"

echo "Creating machine user (if not exists)..."
coder users create \
  --username "$USERNAME" \
  --email "$EMAIL" \
  --login-type none || echo "User may already exist, continuing..."

echo "Upgrading access level of user to template-admin"
coder users edit-roles "$USERNAME" --roles template-admin

echo "Creating long-lived token..."
TOKEN_FILE="$(mktemp -t coder-token)"
chmod 600 "$TOKEN_FILE"
coder tokens create --user "$USERNAME" --lifetime "$TOKEN_LIFETIME" --url "$CODER_URL" |
  tail -n 1 >"$TOKEN_FILE"

# Printing the token would put a year-long template-admin credential into
# terminal scrollback, shell history and any CI log capturing this script.
echo "Token written to $TOKEN_FILE (mode 600)."
echo "Store it in the secret manager, then: shred -u $TOKEN_FILE"
