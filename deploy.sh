#!/bin/bash
set -e

HASH=$(git rev-parse --short HEAD)

# Idempotent: strip any existing ?xxx query strings, then add new hash
# Handles: href="style.css", href="assets/...", src="assets/...", content="...assets/..."
for file in index.html docs.html docs/*.html; do
    if [ -f "$file" ]; then
        sed -i -E -e 's/href="(\.\.\/)?style\.css(\?[^"]*)?"/href="\1style.css?'$HASH'"/g' -e 's/((href|src|content)="[^"]*(\.\.\/)?assets\/[^"?]+)(\?[^"]*)?"/\1?'$HASH'"/g' "$file"
    fi
done

echo "Cache buster updated to: $HASH"