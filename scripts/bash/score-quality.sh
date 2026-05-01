#!/usr/bin/env bash
# score-quality.sh — Analyze an artifact file against expected sections
# Computes quality score components per plan.md "Quality Evaluation" section
#
# Usage:
#   score-quality.sh --command <command-name> [--json] <artifact-file>

set -euo pipefail

# --- Argument parsing ---
COMMAND_NAME=""
JSON_OUTPUT=false
ARTIFACT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --command)  COMMAND_NAME="$2"; shift 2 ;;
        --json)     JSON_OUTPUT=true; shift ;;
        -h|--help)
            echo "Usage: score-quality.sh --command <command-name> [--json] <artifact-file>"
            echo "  Analyzes artifact quality against expected sections for the given command."
            exit 0
            ;;
        *)
            if [[ -z "$ARTIFACT_FILE" ]]; then
                ARTIFACT_FILE="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$COMMAND_NAME" || -z "$ARTIFACT_FILE" ]]; then
    echo "Error: --command and artifact file path are required" >&2
    exit 1
fi

if [[ ! -f "$ARTIFACT_FILE" ]]; then
    echo "Error: File not found: $ARTIFACT_FILE" >&2
    exit 1
fi

# --- Define expected sections per command ---
get_expected_sections() {
    case "$1" in
        specify)
            echo "user-stories acceptance-criteria requirements assumptions"
            ;;
        plan)
            echo "architecture components data-model implementation-approach"
            ;;
        tasks)
            echo "tasks dependencies"
            ;;
        implement)
            echo "implementation"
            ;;
        checklist)
            echo "checklist verification"
            ;;
        clarify)
            echo "questions clarifications"
            ;;
        constitution)
            echo "principles guidelines standards"
            ;;
        analyze)
            echo "analysis findings recommendations"
            ;;
        *)
            echo "content"
            ;;
    esac
}

EXPECTED_SECTIONS=$(get_expected_sections "$COMMAND_NAME")
EXPECTED_COUNT=0
for _ in $EXPECTED_SECTIONS; do
    EXPECTED_COUNT=$((EXPECTED_COUNT + 1))
done

# --- Read artifact ---
ARTIFACT_CONTENT=$(cat "$ARTIFACT_FILE")
ARTIFACT_SIZE=${#ARTIFACT_CONTENT}
ARTIFACT_LINES=$(wc -l < "$ARTIFACT_FILE" | tr -d ' ')

# --- Score: section_completeness (0.3) ---
FOUND_COUNT=0
FOUND_SECTIONS=""
MISSING_SECTIONS=""

for section in $EXPECTED_SECTIONS; do
    # Search case-insensitively for section headers or keywords
    # Replace hyphens with regex alternation for space-or-hyphen matching
    PATTERN=$(echo "$section" | sed 's/-/[[:space:]-]/g')
    if echo "$ARTIFACT_CONTENT" | grep -qiE "$PATTERN"; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        FOUND_SECTIONS="${FOUND_SECTIONS}\"${section}\","
    else
        MISSING_SECTIONS="${MISSING_SECTIONS}\"${section}\","
    fi
done

# Remove trailing commas
FOUND_SECTIONS="${FOUND_SECTIONS%,}"
MISSING_SECTIONS="${MISSING_SECTIONS%,}"

if [[ $EXPECTED_COUNT -gt 0 ]]; then
    # Use awk for floating point division
    SECTION_COMPLETENESS=$(awk "BEGIN {printf \"%.2f\", $FOUND_COUNT / $EXPECTED_COUNT}")
else
    SECTION_COMPLETENESS="1.00"
fi

# --- Score: content_depth (0.25) ---
# Heuristic: sections with >100 chars are "substantive"
H2_COUNT=$(echo "$ARTIFACT_CONTENT" | grep -c '^## ' || true)
TOTAL_CONTENT_CHARS=$ARTIFACT_SIZE

if [[ $H2_COUNT -gt 0 ]]; then
    AVG_SECTION_SIZE=$((TOTAL_CONTENT_CHARS / H2_COUNT))
    if [[ $AVG_SECTION_SIZE -ge 500 ]]; then
        CONTENT_DEPTH="1.00"
    elif [[ $AVG_SECTION_SIZE -ge 200 ]]; then
        CONTENT_DEPTH="0.75"
    elif [[ $AVG_SECTION_SIZE -ge 100 ]]; then
        CONTENT_DEPTH="0.50"
    else
        CONTENT_DEPTH="0.25"
    fi
else
    # No sections — score based on total size
    if [[ $TOTAL_CONTENT_CHARS -ge 1000 ]]; then
        CONTENT_DEPTH="0.75"
    elif [[ $TOTAL_CONTENT_CHARS -ge 500 ]]; then
        CONTENT_DEPTH="0.50"
    else
        CONTENT_DEPTH="0.25"
    fi
fi

# --- Score: cross_reference_accuracy (0.2) ---
# Check for references to other artifacts (spec.md, plan.md, tasks.md, etc.)
REF_COUNT=0
for ref_pattern in "spec.md" "plan.md" "tasks.md" "checklist.md" "constitution.md" "data-model"; do
    if echo "$ARTIFACT_CONTENT" | grep -qi "$ref_pattern"; then
        REF_COUNT=$((REF_COUNT + 1))
    fi
done

# Cross-references are more relevant for later commands
case "$COMMAND_NAME" in
    specify)     EXPECTED_REFS=0 ;;
    plan)        EXPECTED_REFS=1 ;;
    tasks)       EXPECTED_REFS=2 ;;
    implement)   EXPECTED_REFS=2 ;;
    *)           EXPECTED_REFS=0 ;;
esac

if [[ $EXPECTED_REFS -eq 0 ]]; then
    CROSS_REF="1.00"
elif [[ $REF_COUNT -ge $EXPECTED_REFS ]]; then
    CROSS_REF="1.00"
else
    CROSS_REF=$(awk "BEGIN {printf \"%.2f\", $REF_COUNT / $EXPECTED_REFS}")
fi

# --- Score: actionability (0.15) ---
# Check for actionable markers: checkboxes, numbered lists, specific terms
CHECKBOX_COUNT=$(echo "$ARTIFACT_CONTENT" | grep -c '\- \[' || true)
NUMBERED_LIST=$(echo "$ARTIFACT_CONTENT" | grep -c '^[0-9]\+\.' || true)
ACTION_MARKERS=$((CHECKBOX_COUNT + NUMBERED_LIST))

if [[ $ACTION_MARKERS -ge 10 ]]; then
    ACTIONABILITY="1.00"
elif [[ $ACTION_MARKERS -ge 5 ]]; then
    ACTIONABILITY="0.75"
elif [[ $ACTION_MARKERS -ge 2 ]]; then
    ACTIONABILITY="0.50"
else
    ACTIONABILITY="0.25"
fi

# --- Score: format_compliance (0.1) ---
# Check for proper markdown structure
HAS_H1=$(echo "$ARTIFACT_CONTENT" | grep -c '^# ' || true)
HAS_H2=$(echo "$ARTIFACT_CONTENT" | grep -c '^## ' || true)
HAS_FRONTMATTER=$(head -1 "$ARTIFACT_FILE" | grep -c '^---' || true)

FORMAT_POINTS=0
[[ $HAS_H1 -ge 1 ]] && FORMAT_POINTS=$((FORMAT_POINTS + 1))
[[ $HAS_H2 -ge 1 ]] && FORMAT_POINTS=$((FORMAT_POINTS + 1))
[[ $ARTIFACT_LINES -ge 10 ]] && FORMAT_POINTS=$((FORMAT_POINTS + 1))

if [[ $FORMAT_POINTS -ge 3 ]]; then
    FORMAT_COMPLIANCE="1.00"
elif [[ $FORMAT_POINTS -ge 2 ]]; then
    FORMAT_COMPLIANCE="0.75"
elif [[ $FORMAT_POINTS -ge 1 ]]; then
    FORMAT_COMPLIANCE="0.50"
else
    FORMAT_COMPLIANCE="0.25"
fi

# --- Compute overall quality score ---
# quality_score = section_completeness*0.3 + content_depth*0.25 + cross_ref*0.2 + actionability*0.15 + format*0.1
QUALITY_SCORE=$(awk "BEGIN {printf \"%.2f\", $SECTION_COMPLETENESS*0.3 + $CONTENT_DEPTH*0.25 + $CROSS_REF*0.2 + $ACTIONABILITY*0.15 + $FORMAT_COMPLIANCE*0.1}")

# --- Check minimum viable threshold ---
MEETS_THRESHOLD="true"
for score in $SECTION_COMPLETENESS $CONTENT_DEPTH $CROSS_REF $ACTIONABILITY $FORMAT_COMPLIANCE; do
    if awk "BEGIN {exit !($score < 0.5)}"; then
        MEETS_THRESHOLD="false"
    fi
done
if awk "BEGIN {exit !($QUALITY_SCORE < 0.75)}"; then
    MEETS_THRESHOLD="false"
fi

# --- Output ---
if [[ "$JSON_OUTPUT" == true ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg command "$COMMAND_NAME" \
            --arg artifact "$ARTIFACT_FILE" \
            --argjson artifact_size "$ARTIFACT_SIZE" \
            --argjson section_completeness "$SECTION_COMPLETENESS" \
            --argjson content_depth "$CONTENT_DEPTH" \
            --argjson cross_reference_accuracy "$CROSS_REF" \
            --argjson actionability "$ACTIONABILITY" \
            --argjson format_compliance "$FORMAT_COMPLIANCE" \
            --argjson quality_score "$QUALITY_SCORE" \
            --argjson meets_threshold "$MEETS_THRESHOLD" \
            --argjson sections_found "$FOUND_COUNT" \
            --argjson sections_expected "$EXPECTED_COUNT" \
            '{
                command: $command,
                artifact: $artifact,
                artifact_size_bytes: $artifact_size,
                scores: {
                    section_completeness: $section_completeness,
                    content_depth: $content_depth,
                    cross_reference_accuracy: $cross_reference_accuracy,
                    actionability: $actionability,
                    format_compliance: $format_compliance
                },
                quality_score: $quality_score,
                meets_minimum_threshold: $meets_threshold,
                sections_found: $sections_found,
                sections_expected: $sections_expected
            }' 
    else
        cat <<EOF
{
  "command": "${COMMAND_NAME}",
  "artifact": "${ARTIFACT_FILE}",
  "artifact_size_bytes": ${ARTIFACT_SIZE},
  "scores": {
    "section_completeness": ${SECTION_COMPLETENESS},
    "content_depth": ${CONTENT_DEPTH},
    "cross_reference_accuracy": ${CROSS_REF},
    "actionability": ${ACTIONABILITY},
    "format_compliance": ${FORMAT_COMPLIANCE}
  },
  "quality_score": ${QUALITY_SCORE},
  "meets_minimum_threshold": ${MEETS_THRESHOLD},
  "sections_found": ${FOUND_COUNT},
  "sections_expected": ${EXPECTED_COUNT}
}
EOF
    fi
else
    echo "Quality Score: ${ARTIFACT_FILE}"
    echo "  Command:               ${COMMAND_NAME}"
    echo "  Section completeness:  ${SECTION_COMPLETENESS} (${FOUND_COUNT}/${EXPECTED_COUNT})"
    echo "  Content depth:         ${CONTENT_DEPTH}"
    echo "  Cross-ref accuracy:    ${CROSS_REF}"
    echo "  Actionability:         ${ACTIONABILITY}"
    echo "  Format compliance:     ${FORMAT_COMPLIANCE}"
    echo "  ────────────────────────────"
    echo "  Overall quality:       ${QUALITY_SCORE}"
    echo "  Meets threshold:       ${MEETS_THRESHOLD}"
fi
