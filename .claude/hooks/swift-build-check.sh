#!/bin/bash
# swift-build-check.sh - Verify Swift project builds after editing .swift files
# Exit code 0 = build passed (or not a Swift file), exit code 2 = build failed

# Read tool input from stdin
INPUT=$(cat)

# Extract file path from the JSON input
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('tool_input', {}).get('file_path', data.get('tool_input', {}).get('path', '')))" 2>/dev/null)

# Only check Swift source files
if [[ ! "$FILE_PATH" =~ \.swift$ ]]; then
    exit 0
fi

# Run swift build
cd "$CLAUDE_PROJECT_DIR"

BUILD_OUTPUT=$(swift build 2>&1)
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -ne 0 ]; then
    # Extract just the error lines (last 20 lines to avoid excessive output)
    ERRORS=$(echo "$BUILD_OUTPUT" | tail -20)
    echo "Swift build failed after editing ${FILE_PATH}:" >&2
    echo "" >&2
    echo "$ERRORS" >&2
    echo "" >&2
    echo "Please fix the build errors before continuing." >&2
    exit 2
fi

# Build passed - provide context to Claude
echo "Build passed after editing ${FILE_PATH}"

exit 0