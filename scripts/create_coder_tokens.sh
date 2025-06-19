#!/bin/bash

# This script creates a machine user and generates a long-lived token for Coder
# Usage: ./create_coder_tokens.sh <CODER_URL>
# Example: ./create_coder_tokens.sh https://coder.abridge.coffee/

set -euo pipefail

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
coder users edit-roles $USERNAME --roles template-admin

echo "Creating long-lived token..."
TOKEN=$(coder tokens create --user "$USERNAME" --lifetime "$TOKEN_LIFETIME" --url "$CODER_URL" | tail -n 1)

echo "Token generated: $TOKEN"
