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

echo "Note: Template admin role must be assigned manually via the web UI or a newer CLI version"
# TODO: bump to 2.22.1 and use https://coder.com/docs/@v2.22.1/reference/cli/users_edit-roles

echo "Creating long-lived token..."
TOKEN=$(coder tokens create --user "$USERNAME" --lifetime "$TOKEN_LIFETIME" --url "$CODER_URL" | tail -n 1)

echo "Token generated: $TOKEN"
