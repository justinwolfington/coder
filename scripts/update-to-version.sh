#!/bin/bash

# Simple script to update module references to a version tag
# Usage: ./scripts/update-to-version.sh v1.0.0

VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v1.0.0"
    exit 1
fi

echo "Updating all module references to: $VERSION"

# Update all .tf files that have abridgeai/coder.git module references
find . -name "*.tf" -exec sed -i '' "s|git::https://github.com/abridgeai/coder.git//modules/\([^?]*\)?ref=[^\"]*|git::https://github.com/abridgeai/coder.git//modules/\1?ref=$VERSION|g" {} \;

echo "Done. Updated all module references to $VERSION"
echo ""
echo "Don't forget to:"
echo "- Check what changed: git diff"
echo "- Commit: git add . && git commit -m 'Update module references to $VERSION'"
echo "- Tag it: git tag $VERSION && git push origin $VERSION"
