#!/usr/bin/env bash
# estimate-tokens.sh — Estimate token count from a markdown file
# Uses character heuristic: 1 token ≈ 4 chars
# Breaks down by markdown section (H2 headers)
#
# Usage:
#   estimate-tokens.sh [--json] <markdown-file>

set -euo pipefail

# --- Argument parsing ---
JSON_OUTPUT=false
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_OUTPUT=true; shift ;;
        -h|--help)
            echo "Usage: estimate-tokens.sh [--json] <markdown-file>"
            echo "  Estimates token count using character heuristic (1 token ≈ 4 chars)."
            exit 0
            ;;
        *)
            if [[ -z "$INPUT_FILE" ]]; then
                INPUT_FILE="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: Markdown file path required" >&2
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File not found: $INPUT_FILE" >&2
    exit 1
fi

# --- Parse sections ---
# Read file and split by H2 headers (## )
TOTAL_CHARS=0
TOTAL_LINES=0
SECTION_NAME="(preamble)"
SECTION_CHARS=0
SECTION_DATA=""
FIRST=true

while IFS= read -r line || [[ -n "$line" ]]; do
    TOTAL_LINES=$((TOTAL_LINES + 1))
    LINE_LEN=${#line}
    TOTAL_CHARS=$((TOTAL_CHARS + LINE_LEN))

    if [[ "$line" =~ ^##[[:space:]]+(.+) ]]; then
        # Save previous section
        if [[ "$FIRST" == true ]]; then
            FIRST=false
        fi
        SECTION_TOKENS=$(( (SECTION_CHARS + 3) / 4 ))
        if [[ -n "$SECTION_DATA" ]]; then
            SECTION_DATA="${SECTION_DATA},"
        fi
        # Sanitize section name for JSON
        SAFE_NAME=$(echo "$SECTION_NAME" | sed 's/"/\\"/g')
        SECTION_DATA="${SECTION_DATA}{\"section\":\"${SAFE_NAME}\",\"chars\":${SECTION_CHARS},\"estimated_tokens\":${SECTION_TOKENS}}"

        # Start new section
        SECTION_NAME="${BASH_REMATCH[1]}"
        SECTION_CHARS=0
    else
        SECTION_CHARS=$((SECTION_CHARS + LINE_LEN))
    fi
done < "$INPUT_FILE"

# Save last section
SECTION_TOKENS=$(( (SECTION_CHARS + 3) / 4 ))
if [[ -n "$SECTION_DATA" ]]; then
    SECTION_DATA="${SECTION_DATA},"
fi
SAFE_NAME=$(echo "$SECTION_NAME" | sed 's/"/\\"/g')
SECTION_DATA="${SECTION_DATA}{\"section\":\"${SAFE_NAME}\",\"chars\":${SECTION_CHARS},\"estimated_tokens\":${SECTION_TOKENS}}"

# --- Compute totals ---
TOTAL_ESTIMATED=$(( (TOTAL_CHARS + 3) / 4 ))

# --- Output ---
if [[ "$JSON_OUTPUT" == true ]]; then
    if command -v jq >/dev/null 2>&1; then
        echo "{\"file\":\"${INPUT_FILE}\",\"total_chars\":${TOTAL_CHARS},\"total_lines\":${TOTAL_LINES},\"total_estimated_tokens\":${TOTAL_ESTIMATED},\"sections\":[${SECTION_DATA}]}" | jq .
    else
        cat <<EOF
{
  "file": "${INPUT_FILE}",
  "total_chars": ${TOTAL_CHARS},
  "total_lines": ${TOTAL_LINES},
  "total_estimated_tokens": ${TOTAL_ESTIMATED},
  "sections": [${SECTION_DATA}]
}
EOF
    fi
else
    echo "Token Estimate: ${INPUT_FILE}"
    echo "  Total characters: ${TOTAL_CHARS}"
    echo "  Total lines:      ${TOTAL_LINES}"
    echo "  Estimated tokens: ${TOTAL_ESTIMATED}"
    echo ""
    echo "  Breakdown by section:"
    # Parse section data for display
    echo "$SECTION_DATA" | tr ',' '\n' | while read -r entry; do
        SEC=$(echo "$entry" | sed 's/.*"section":"\([^"]*\)".*/\1/')
        TOK=$(echo "$entry" | sed 's/.*"estimated_tokens":\([0-9]*\).*/\1/')
        printf "    %-40s %s tokens\n" "$SEC" "$TOK"
    done
fi
