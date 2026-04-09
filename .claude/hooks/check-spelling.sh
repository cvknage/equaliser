#!/bin/bash
# check-spelling.sh - British English spelling check for Equaliser project
# Blocks Write/Edit calls that introduce American English spellings
# Exit code 2 = block with error message, exit code 0 = allow

# Read tool input from stdin
INPUT=$(cat)

# Extract file path from the JSON input
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('tool_input', {}).get('file_path', data.get('tool_input', {}).get('path', '')))" 2>/dev/null)

# Only check Swift source files
if [[ ! "$FILE_PATH" =~ \.swift$ ]]; then
    exit 0
fi

# Read the file content from the tool input
CONTENT=$(echo "$INPUT" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('tool_input', {}).get('content', data.get('tool_input', {}).get('new_string', '')))" 2>/dev/null)

if [ -z "$CONTENT" ]; then
    # For Edit operations, we need to read the diff content
    CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
content = tool_input.get('content', '')
if not content:
    content = tool_input.get('new_string', '')
print(content)
" 2>/dev/null)
fi

if [ -z "$CONTENT" ]; then
    exit 0
fi

# Check for American English spellings
# Format: "wrong -> correct"
SPELLING_ERRORS=""

# Check each pattern (case-sensitive for code, case-insensitive for comments)
check_spelling() {
    local wrong="$1"
    local correct="$2"
    local content="$3"

    # For code identifiers, check exact match
    if grep -qE "\b${wrong}\b" <<< "$content" 2>/dev/null; then
        SPELLING_ERRORS="${SPELLING_ERRORS}\n  ${wrong} → ${correct}"
    fi
}

check_spelling_ci() {
    local wrong="$1"
    local correct="$2"
    local content="$3"

    if grep -qiE "\b${wrong}\b" <<< "$content" 2>/dev/null; then
        SPELLING_ERRORS="${SPELLING_ERRORS}\n  ${wrong} → ${correct}"
    fi
}

# Code-level checks (case-sensitive - these are identifiers/string literals)
check_spelling "equalizer" "equaliser" "$CONTENT"
check_spelling "Equalizer" "Equaliser" "$CONTENT"

# Comment/string-level checks (case-insensitive)
check_spelling_ci "behavior" "behaviour" "$CONTENT"
check_spelling_ci "optimized" "optimised" "$CONTENT"
check_spelling_ci "initialize" "initialise" "$CONTENT"
check_spelling_ci "categorize" "categorise" "$CONTENT"
check_spelling_ci "summarize" "summarise" "$CONTENT"
check_spelling_ci "color" "colour" "$CONTENT"
check_spelling_ci "center" "centre" "$CONTENT"
check_spelling_ci "organize" "organise" "$CONTENT"
check_spelling_ci "recognize" "recognise" "$CONTENT"
check_spelling_ci "minimize" "minimise" "$CONTENT"
check_spelling_ci "maximize" "maximise" "$CONTENT"
check_spelling_ci "standardize" "standardise" "$CONTENT"
check_spelling_ci "synchronize" "synchronise" "$CONTENT"

if [ -n "$SPELLING_ERRORS" ]; then
    echo "British English spelling violations found in ${FILE_PATH}:${SPELLING_ERRORS}" >&2
    echo "" >&2
    echo "This project uses British English. Please use the suggested replacements." >&2
    exit 2
fi

exit 0