#!/bin/bash
set -e

HASH=$(git rev-parse --short HEAD)

# Idempotent: strip any existing ?xxx query strings, then add new hash
# Handles: href="style.css", href="assets/...", src="assets/...", content="...assets/..."
sed -i -E -e 's/href="style\.css(\?[^"]*)?"/href="style.css?'$HASH'"/g' -e 's/((href|src|content)="[^"]*assets\/[^"?]+)(\?[^"]*)?"/\1?'$HASH'"/g' index.html

echo "Cache buster updated to: $HASH"