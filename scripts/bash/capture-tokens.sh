#!/usr/bin/env bash
# capture-tokens.sh — Parse CLI JSON response for token fields
# Writes per-step JSON to .specify/token-analysis/runs/{label}/steps/
#
# Usage:
#   capture-tokens.sh --run-label <label> --step <command> [--json] < cli-response.json
#   capture-tokens.sh --run-label <label> --step <command> [--json] --file <path>

set -euo pipefail

# --- Argument parsing ---
RUN_LABEL=""
STEP_NAME=""
JSON_OUTPUT=false
INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-label) RUN_LABEL="$2"; shift 2 ;;
        --step)      STEP_NAME="$2"; shift 2 ;;
        --json)      JSON_OUTPUT=true; shift ;;
        --file)      INPUT_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: capture-tokens.sh --run-label <label> --step <command> [--json] [--file <path>]"
            echo "  Reads CLI JSON response from stdin or --file, extracts token metrics."
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$RUN_LABEL" || -z "$STEP_NAME" ]]; then
    echo "Error: --run-label and --step are required" >&2
    exit 1
fi

# --- Read input ---
if [[ -n "$INPUT_FILE" ]]; then
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "Error: File not found: $INPUT_FILE" >&2
        exit 1
    fi
    RAW_INPUT=$(cat "$INPUT_FILE")
else
    RAW_INPUT=$(cat)
fi

# --- Output directory ---
DATA_DIR=".specify/token-analysis/runs/${RUN_LABEL}/steps"
mkdir -p "$DATA_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# --- Parse token fields ---
# Supports three provider formats:
#   - Anthropic/Claude: input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens
#   - OpenAI/Copilot:   prompt_tokens, completion_tokens, total_tokens
#   - Google Gemini:    promptTokenCount, candidatesTokenCount, totalTokenCount, cachedContentTokenCount

# Try jq first, fall back to grep/sed
extract_field() {
    local field="$1"
    local default="$2"
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_INPUT" | jq -r ".. | .${field}? // empty" 2>/dev/null | head -1
    else
        echo "$RAW_INPUT" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[0-9]*" | head -1 | grep -o '[0-9]*$'
    fi | head -1 || echo "$default"
}

extract_string_field() {
    local field="$1"
    local default="$2"
    if command -v jq >/dev/null 2>&1; then
        echo "$RAW_INPUT" | jq -r ".. | .${field}? // empty" 2>/dev/null | head -1
    else
        echo "$RAW_INPUT" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*: *"\([^"]*\)"/\1/'
    fi | head -1 || echo "$default"
}

# Try first field, fall back to second, then third
extract_field_multi() {
    local default="$1"; shift
    for field in "$@"; do
        local val
        val=$(extract_field "$field" "")
        if [[ -n "$val" && "$val" != "0" ]]; then
            echo "$val"
            return
        fi
    done
    echo "$default"
}

extract_string_field_multi() {
    local default="$1"; shift
    for field in "$@"; do
        local val
        val=$(extract_string_field "$field" "")
        if [[ -n "$val" && "$val" != "unknown" && "$val" != "" ]]; then
            echo "$val"
            return
        fi
    done
    echo "$default"
}

# Input tokens:  Claude input_tokens → OpenAI prompt_tokens → Gemini promptTokenCount
INPUT_TOKENS=$(extract_field_multi "0" "input_tokens" "prompt_tokens" "promptTokenCount")

# Output tokens: Claude output_tokens → OpenAI completion_tokens → Gemini candidatesTokenCount
OUTPUT_TOKENS=$(extract_field_multi "0" "output_tokens" "completion_tokens" "candidatesTokenCount")

# Cache read:    Claude cache_read_input_tokens → Gemini cachedContentTokenCount
CACHE_READ=$(extract_field_multi "0" "cache_read_input_tokens" "cachedContentTokenCount")

# Cache creation: Claude only
CACHE_CREATION=$(extract_field "cache_creation_input_tokens" "0")

# Model: universal "model" field → Gemini "modelVersion"
MODEL=$(extract_string_field_multi "unknown" "model" "modelVersion")

# Stop reason: Claude stop_reason → OpenAI finish_reason → Gemini finishReason
STOP_REASON=$(extract_string_field_multi "unknown" "stop_reason" "finish_reason" "finishReason")

# Handle empty values
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}
CACHE_READ=${CACHE_READ:-0}
CACHE_CREATION=${CACHE_CREATION:-0}

TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))

# --- Write step JSON ---
OUTPUT_PATH="${DATA_DIR}/${STEP_NAME}.json"

if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg command "speckit.${STEP_NAME}" \
        --arg model "$MODEL" \
        --arg timestamp "$TIMESTAMP" \
        --arg stop_reason "$STOP_REASON" \
        --argjson input_tokens "$INPUT_TOKENS" \
        --argjson output_tokens "$OUTPUT_TOKENS" \
        --argjson total_tokens "$TOTAL_TOKENS" \
        --argjson cache_read "$CACHE_READ" \
        --argjson cache_creation "$CACHE_CREATION" \
        '{
            command: $command,
            model: $model,
            timestamp: $timestamp,
            stop_reason: $stop_reason,
            tokens: {
                input: $input_tokens,
                output: $output_tokens,
                total: $total_tokens,
                cache_read: $cache_read,
                cache_creation: $cache_creation
            }
        }' > "$OUTPUT_PATH"
else
    cat > "$OUTPUT_PATH" <<EOF
{
  "command": "speckit.${STEP_NAME}",
  "model": "${MODEL}",
  "timestamp": "${TIMESTAMP}",
  "stop_reason": "${STOP_REASON}",
  "tokens": {
    "input": ${INPUT_TOKENS},
    "output": ${OUTPUT_TOKENS},
    "total": ${TOTAL_TOKENS},
    "cache_read": ${CACHE_READ},
    "cache_creation": ${CACHE_CREATION}
  }
}
EOF
fi

# --- Output ---
if [[ "$JSON_OUTPUT" == true ]]; then
    cat "$OUTPUT_PATH"
else
    echo "Captured tokens for ${STEP_NAME}:"
    echo "  Input:          ${INPUT_TOKENS}"
    echo "  Output:         ${OUTPUT_TOKENS}"
    echo "  Total:          ${TOTAL_TOKENS}"
    echo "  Cache read:     ${CACHE_READ}"
    echo "  Cache creation: ${CACHE_CREATION}"
    echo "  Model:          ${MODEL}"
    echo "  Saved to:       ${OUTPUT_PATH}"
fi
