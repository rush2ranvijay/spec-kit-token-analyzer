#!/usr/bin/env bash
# generate-report.sh — Aggregate step JSONs for a run into summary.json and markdown report
#
# Usage:
#   generate-report.sh --run-label <label> [--json]

set -euo pipefail

# --- Argument parsing ---
RUN_LABEL=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-label) RUN_LABEL="$2"; shift 2 ;;
        --json)      JSON_OUTPUT=true; shift ;;
        -h|--help)
            echo "Usage: generate-report.sh --run-label <label> [--json]"
            echo "  Aggregates step JSONs into summary.json and renders a markdown report."
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$RUN_LABEL" ]]; then
    echo "Error: --run-label is required" >&2
    exit 1
fi

RUN_DIR=".specify/token-analysis/runs/${RUN_LABEL}"
STEPS_DIR="${RUN_DIR}/steps"

if [[ ! -d "$STEPS_DIR" ]]; then
    echo "Error: No steps found at ${STEPS_DIR}" >&2
    exit 1
fi

# --- Aggregate step data ---
TOTAL_INPUT=0
TOTAL_OUTPUT=0
TOTAL_TOKENS=0
TOTAL_CACHE_READ=0
TOTAL_CACHE_CREATION=0
STEP_COUNT=0
STEPS_JSON=""
MODEL="unknown"

for step_file in "${STEPS_DIR}"/*.json; do
    [[ -f "$step_file" ]] || continue
    STEP_COUNT=$((STEP_COUNT + 1))

    if command -v jq >/dev/null 2>&1; then
        S_INPUT=$(jq -r '.tokens.input // 0' "$step_file")
        S_OUTPUT=$(jq -r '.tokens.output // 0' "$step_file")
        S_TOTAL=$(jq -r '.tokens.total // 0' "$step_file")
        S_CACHE_READ=$(jq -r '.tokens.cache_read // 0' "$step_file")
        S_CACHE_CREATION=$(jq -r '.tokens.cache_creation // 0' "$step_file")
        S_COMMAND=$(jq -r '.command // "unknown"' "$step_file")
        MODEL=$(jq -r '.model // "unknown"' "$step_file")
    else
        S_INPUT=$(grep -o '"input"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$' || echo 0)
        S_OUTPUT=$(grep -o '"output"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$' || echo 0)
        S_TOTAL=$(grep -o '"total"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | head -1 | grep -o '[0-9]*$' || echo 0)
        S_CACHE_READ=$(grep -o '"cache_read"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$' || echo 0)
        S_CACHE_CREATION=$(grep -o '"cache_creation"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$' || echo 0)
        S_COMMAND=$(grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$step_file" | sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown")
        MODEL=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$step_file" | sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown")
    fi

    TOTAL_INPUT=$((TOTAL_INPUT + S_INPUT))
    TOTAL_OUTPUT=$((TOTAL_OUTPUT + S_OUTPUT))
    TOTAL_TOKENS=$((TOTAL_TOKENS + S_TOTAL))
    TOTAL_CACHE_READ=$((TOTAL_CACHE_READ + S_CACHE_READ))
    TOTAL_CACHE_CREATION=$((TOTAL_CACHE_CREATION + S_CACHE_CREATION))

    if [[ -n "$STEPS_JSON" ]]; then
        STEPS_JSON="${STEPS_JSON},"
    fi
    STEPS_JSON="${STEPS_JSON}{\"command\":\"${S_COMMAND}\",\"input\":${S_INPUT},\"output\":${S_OUTPUT},\"total\":${S_TOTAL}}"
done

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# --- Read metadata ---
SCENARIO=""
PRESET=""
if [[ -f "${RUN_DIR}/metadata.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
        SCENARIO=$(jq -r '.scenario // ""' "${RUN_DIR}/metadata.json")
        PRESET=$(jq -r '.preset // "standard"' "${RUN_DIR}/metadata.json")
    fi
fi

# --- Write summary.json ---
SUMMARY_PATH="${RUN_DIR}/summary.json"

if command -v jq >/dev/null 2>&1; then
    jq -n \
        --arg run_label "$RUN_LABEL" \
        --arg scenario "$SCENARIO" \
        --arg preset "$PRESET" \
        --arg model "$MODEL" \
        --arg timestamp "$TIMESTAMP" \
        --argjson step_count "$STEP_COUNT" \
        --argjson total_input "$TOTAL_INPUT" \
        --argjson total_output "$TOTAL_OUTPUT" \
        --argjson total_tokens "$TOTAL_TOKENS" \
        --argjson cache_read "$TOTAL_CACHE_READ" \
        --argjson cache_creation "$TOTAL_CACHE_CREATION" \
        --argjson steps "[$STEPS_JSON]" \
        '{
            run_label: $run_label,
            scenario: $scenario,
            preset: $preset,
            model: $model,
            timestamp: $timestamp,
            step_count: $step_count,
            tokens: {
                total_input: $total_input,
                total_output: $total_output,
                total: $total_tokens,
                cache_read: $cache_read,
                cache_creation: $cache_creation
            },
            steps: $steps
        }' > "$SUMMARY_PATH"
else
    cat > "$SUMMARY_PATH" <<EOF
{
  "run_label": "${RUN_LABEL}",
  "scenario": "${SCENARIO}",
  "preset": "${PRESET}",
  "model": "${MODEL}",
  "timestamp": "${TIMESTAMP}",
  "step_count": ${STEP_COUNT},
  "tokens": {
    "total_input": ${TOTAL_INPUT},
    "total_output": ${TOTAL_OUTPUT},
    "total": ${TOTAL_TOKENS},
    "cache_read": ${TOTAL_CACHE_READ},
    "cache_creation": ${TOTAL_CACHE_CREATION}
  },
  "steps": [${STEPS_JSON}]
}
EOF
fi

# --- Generate markdown report ---
REPORT_PATH="${RUN_DIR}/report.md"

cat > "$REPORT_PATH" <<EOF
# Token Analysis Report: ${RUN_LABEL}

Generated: ${TIMESTAMP}
Scenario: ${SCENARIO}
Preset: ${PRESET}
Model: ${MODEL}

## Summary

| Metric | Value |
|--------|-------|
| Steps captured | ${STEP_COUNT} |
| Total input tokens | ${TOTAL_INPUT} |
| Total output tokens | ${TOTAL_OUTPUT} |
| Total tokens | ${TOTAL_TOKENS} |
| Cache read tokens | ${TOTAL_CACHE_READ} |
| Cache creation tokens | ${TOTAL_CACHE_CREATION} |

## Per-Step Breakdown

| Command | Input | Output | Total |
|---------|-------|--------|-------|
EOF

# Add per-step rows
for step_file in "${STEPS_DIR}"/*.json; do
    [[ -f "$step_file" ]] || continue
    if command -v jq >/dev/null 2>&1; then
        S_CMD=$(jq -r '.command // "unknown"' "$step_file")
        S_IN=$(jq -r '.tokens.input // 0' "$step_file")
        S_OUT=$(jq -r '.tokens.output // 0' "$step_file")
        S_TOT=$(jq -r '.tokens.total // 0' "$step_file")
    else
        S_CMD=$(grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$step_file" | sed 's/.*"\([^"]*\)"$/\1/')
        S_IN=$(grep -o '"input"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$')
        S_OUT=$(grep -o '"output"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | grep -o '[0-9]*$')
        S_TOT=$(grep -o '"total"[[:space:]]*:[[:space:]]*[0-9]*' "$step_file" | head -1 | grep -o '[0-9]*$')
    fi
    echo "| ${S_CMD} | ${S_IN} | ${S_OUT} | ${S_TOT} |" >> "$REPORT_PATH"
done

# --- Output ---
if [[ "$JSON_OUTPUT" == true ]]; then
    cat "$SUMMARY_PATH"
else
    cat "$REPORT_PATH"
fi
