# Token Analysis: {{COMPARISON_NAME}}

Generated: {{TIMESTAMP}}

## Run Details

| Property | Baseline | Variant |
|----------|----------|---------|
| Run label | {{BASELINE_LABEL}} | {{VARIANT_LABEL}} |
| Scenario | {{SCENARIO}} | {{SCENARIO}} |
| Preset | {{BASELINE_PRESET}} | {{VARIANT_PRESET}} |
| Model | {{BASELINE_MODEL}} | {{VARIANT_MODEL}} |
| Steps | {{BASELINE_STEPS}} | {{VARIANT_STEPS}} |

## Token Summary

| Metric | Baseline | Variant | Delta | Change |
|--------|----------|---------|-------|--------|
| Input tokens | {{BASELINE_INPUT}} | {{VARIANT_INPUT}} | {{DELTA_INPUT}} | {{PCT_INPUT}}% |
| Output tokens | {{BASELINE_OUTPUT}} | {{VARIANT_OUTPUT}} | {{DELTA_OUTPUT}} | {{PCT_OUTPUT}}% |
| Total tokens | {{BASELINE_TOTAL}} | {{VARIANT_TOTAL}} | {{DELTA_TOTAL}} | {{PCT_TOTAL}}% |
| Cache read | {{BASELINE_CACHE_READ}} | {{VARIANT_CACHE_READ}} | {{DELTA_CACHE_READ}} | {{PCT_CACHE_READ}}% |
| Cache creation | {{BASELINE_CACHE_CREATE}} | {{VARIANT_CACHE_CREATE}} | {{DELTA_CACHE_CREATE}} | {{PCT_CACHE_CREATE}}% |

## Per-Step Breakdown

| Command | Baseline Tokens | Variant Tokens | Reduction |
|---------|----------------|----------------|-----------|
{{STEP_ROWS}}

## Quality Comparison

| Factor | Weight | Baseline | Variant | Delta |
|--------|--------|----------|---------|-------|
| Section completeness | 0.30 | {{BL_COMPLETENESS}} | {{VR_COMPLETENESS}} | {{D_COMPLETENESS}} |
| Content depth | 0.25 | {{BL_DEPTH}} | {{VR_DEPTH}} | {{D_DEPTH}} |
| Cross-reference accuracy | 0.20 | {{BL_CROSSREF}} | {{VR_CROSSREF}} | {{D_CROSSREF}} |
| Actionability | 0.15 | {{BL_ACTION}} | {{VR_ACTION}} | {{D_ACTION}} |
| Format compliance | 0.10 | {{BL_FORMAT}} | {{VR_FORMAT}} | {{D_FORMAT}} |
| **Overall** | **1.00** | **{{BL_QUALITY}}** | **{{VR_QUALITY}}** | **{{D_QUALITY}}** |

## Efficiency Analysis

| Metric | Baseline | Variant | Change |
|--------|----------|---------|--------|
| Quality per kilotokens | {{BL_EFFICIENCY}} | {{VR_EFFICIENCY}} | {{D_EFFICIENCY}}% |
| Token reduction | — | — | {{TOKEN_REDUCTION}}% |
| Quality delta | — | — | {{QUALITY_DELTA}} |

## Acceptance Criteria

| Criterion | Required | Actual | Pass |
|-----------|----------|--------|------|
| Token reduction > 10% | > 10% | {{TOKEN_REDUCTION}}% | {{PASS_REDUCTION}} |
| Quality delta > -0.1 | > -0.1 | {{QUALITY_DELTA}} | {{PASS_QUALITY}} |
| Efficiency improves | Positive | {{D_EFFICIENCY}}% | {{PASS_EFFICIENCY}} |

## Recommendation

**{{RECOMMENDATION}}**: {{RECOMMENDATION_RATIONALE}}
