#!/bin/bash
# Deploy script for gh-pages landing page
# Updates cache-busting hashes and commits changes

set -e

# Get short git hash
HASH=$(git rev-parse --short HEAD)

# Remove any existing cache buster query strings first, then add new one
# Using a temp file for macOS sed compatibility
TEMP_FILE=$(mktemp)

# Process index.html
sed -E "s/(href=\"style\.css)(\?[^\"]*)?\"/\1?$HASH\"/g" index.html > "$TEMP_FILE"
mv "$TEMP_FILE" index.html

sed -E "s/(href=\"assets\/[^\"]+)(\?[^\"]*)?\"/\1?$HASH\"/g" index.html > "$TEMP_FILE"
mv "$TEMP_FILE" index.html

sed -E "s/(src=\"assets\/[^\"]+)(\?[^\"]*)?\"/\1?$HASH\"/g" index.html > "$TEMP_FILE"
mv "$TEMP_FILE" index.html

echo "Cache buster updated to: $HASH"
echo "Asset URLs updated in index.html"