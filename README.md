# Token Consumption Analyzer

A [spec-kit](https://github.com/github/spec-kit) extension that captures, analyzes, and compares token consumption across Spec-Driven Development workflows.

*"Does changing my preset, model, or prompt actually save tokens — and at what cost to quality?"*

**Example: Standard preset (90,680 tokens) vs Lean preset (48,200 tokens) — same feature, same model:**

| Command | Standard | Lean | Reduction |
|---------|--------:|------:|----------:|
| `speckit.specify` | 15,680 | 8,000 | 48.9% |
| `speckit.plan` | 19,700 | 10,600 | 46.1% |
| `speckit.tasks` | 24,000 | 12,900 | 46.2% |
| `speckit.implement` | 31,300 | 16,700 | 46.6% |
| **Total** | **90,680** | **48,200** | **46.8%** |

> — Lean preset achieves 46.8% token reduction with quality score delta of only -.07. Efficiency improves by 72.5%.

---

## Installation

```bash
specify extension add token-analyzer
```

For local development:

```bash
specify extension add --dev /path/to/spec-kit-token-analyzer
```

After installation, the extension registers three Copilot commands and four optional hooks.

---

## Quick Start

**1. Capture a baseline** — run a full SDD workflow, then capture the token metrics:

```
/speckit.token-analyzer.baseline standard-greeting --scenario "Add greeting feature" --preset standard
```

**2. Capture a variant** — switch to a different preset and run the same scenario:

```
/speckit.token-analyzer.baseline lean-greeting --scenario "Add greeting feature" --preset lean
```

**3. Compare** — see the deltas:

```
/speckit.token-analyzer.compare standard-vs-lean --baseline standard-greeting --variant lean-greeting
```

---

## Commands

### `speckit.token-analyzer.baseline`

Captures token metrics for each step of an SDD workflow and saves them as a named run.

```
/speckit.token-analyzer.baseline <run-label> [--scenario "..."] [--commands specify,plan,tasks] [--preset lean|standard]
```

For each workflow step, the extension parses the CLI JSON response and writes a per-step file:

```json
{
  "command": "speckit.specify",
  "model": "claude-sonnet-4-20250514",
  "timestamp": "2026-05-01T16:05:10Z",
  "stop_reason": "end_turn",
  "tokens": {
    "input": 12480,
    "output": 3200,
    "total": 15680,
    "cache_read": 1200,
    "cache_creation": 11280
  }
}
```

Once all steps are captured, the extension aggregates them into a summary report. Here's what a 4-step standard-preset run looks like:

| Metric | Value |
|--------|------:|
| Steps captured | 4 |
| Total input tokens | 68,680 |
| Total output tokens | 22,000 |
| **Total tokens** | **90,680** |
| Cache read tokens | 44,700 |
| Cache creation tokens | 23,980 |

<details>
<summary>Per-step breakdown</summary>

| Command | Input | Output | Total |
|---------|------:|-------:|------:|
| `speckit.specify` | 12,480 | 3,200 | 15,680 |
| `speckit.plan` | 15,600 | 4,100 | 19,700 |
| `speckit.tasks` | 18,200 | 5,800 | 24,000 |
| `speckit.implement` | 22,400 | 8,900 | 31,300 |

</details>

---

### `speckit.token-analyzer.compare`

Compares two runs side-by-side, computing deltas for every metric.

```
/speckit.token-analyzer.compare <name> --baseline <run-label> --variant <run-label>
```

Below is a real comparison of the `standard` vs `lean` preset for an "Add greeting feature" scenario — both using `claude-sonnet-4-20250514` across 4 steps:

| Metric | Baseline | Variant | Delta | Change |
|--------|----------|---------|------:|-------:|
| Input tokens | 68,680 | 36,300 | -32,380 | -47.1% |
| Output tokens | 22,000 | 11,900 | -10,100 | -45.9% |
| **Total tokens** | **90,680** | **48,200** | **-42,480** | **-46.8%** |
| Cache read | 44,700 | 23,000 | -21,700 | -48.5% |
| Cache creation | 23,980 | 13,300 | -10,680 | -44.5% |

The comparison scores output quality on five weighted factors and applies acceptance gates:

| Criterion | Required | Actual | Pass |
|-----------|----------|-------:|:----:|
| Token reduction > 10% | > 10% | 46.8% | ✅ |
| Quality delta > -0.1 | > -0.1 | -.07 | ✅ |
| Efficiency improves | Positive | 72.5% | ✅ |

<details>
<summary>Quality scoring breakdown</summary>

| Factor | Weight | Baseline | Variant | Delta |
|--------|-------:|---------:|--------:|------:|
| Section completeness | 0.30 | 0.75 | 0.70 | -0.05 |
| Content depth | 0.25 | 0.75 | 0.65 | -0.10 |
| Cross-reference accuracy | 0.20 | 1.00 | 0.80 | -0.20 |
| Actionability | 0.15 | 0.75 | 0.75 | 0.00 |
| Format compliance | 0.10 | 1.00 | 1.00 | 0.00 |
| **Overall** | **1.00** | **0.83** | **0.76** | **-.07** |

</details>

---

### `speckit.token-analyzer.report`

Generates an analysis report aggregating multiple runs.

```
/speckit.token-analyzer.report <name> [--runs run1,run2] [--format markdown|json]
```

---

## Scripts

The extension ships four scripts (bash + PowerShell) that the commands orchestrate. You can also run them directly.

### `estimate-tokens.sh`

Estimates token count from any markdown file using a character heuristic (1 token ≈ 4 chars), broken down by section.

```bash
.specify/extensions/token-analyzer/scripts/bash/estimate-tokens.sh --json spec.md
```

```json
{
  "file": "spec.md",
  "total_chars": 1293,
  "total_lines": 33,
  "total_estimated_tokens": 324,
  "sections": [
    { "section": "Overview", "chars": 153, "estimated_tokens": 39 },
    { "section": "User Stories", "chars": 263, "estimated_tokens": 66 },
    { "section": "Acceptance Criteria", "chars": 235, "estimated_tokens": 59 },
    { "section": "Requirements", "chars": 535, "estimated_tokens": 134 }
  ]
}
```

### `capture-tokens.sh`

Parses a CLI JSON response for token fields and writes per-step data.

```bash
cat cli-response.json | .specify/extensions/token-analyzer/scripts/bash/capture-tokens.sh \
  --run-label standard-greeting --step specify --json
```

<details>
<summary>JSON output</summary>

```json
{
  "command": "speckit.specify",
  "model": "claude-sonnet-4-20250514",
  "timestamp": "2026-05-01T16:05:10Z",
  "stop_reason": "end_turn",
  "tokens": {
    "input": 12480,
    "output": 3200,
    "total": 15680,
    "cache_read": 1200,
    "cache_creation": 11280
  }
}
```

</details>

<details>
<summary>Human-readable output (without <code>--json</code>)</summary>

```
Captured tokens for specify:
  Input:          9500
  Output:         2800
  Total:          12300
  Cache read:     4000
  Cache creation: 5500
  Model:          claude-sonnet-4-20250514
  Saved to:       .specify/token-analysis/runs/standard-greeting/steps/specify.json
```

</details>

### `score-quality.sh`

Scores an SDD artifact on five weighted factors.

```bash
.specify/extensions/token-analyzer/scripts/bash/score-quality.sh --json spec.md --command specify
```

```json
{
  "command": "specify",
  "artifact": "spec.md",
  "artifact_size_bytes": 1325,
  "scores": {
    "section_completeness": 0.75,
    "content_depth": 0.75,
    "cross_reference_accuracy": 1.00,
    "actionability": 0.75,
    "format_compliance": 1.00
  },
  "quality_score": 0.83,
  "meets_minimum_threshold": true,
  "sections_found": 3,
  "sections_expected": 4
}
```

| Factor | Weight |
|--------|-------:|
| Section completeness | 0.30 |
| Content depth | 0.25 |
| Cross-reference accuracy | 0.20 |
| Actionability | 0.15 |
| Format compliance | 0.10 |

### `generate-report.sh`

Aggregates all step JSONs for a run into `summary.json` and a markdown report.

```bash
.specify/extensions/token-analyzer/scripts/bash/generate-report.sh --run-label standard-greeting
```

<details>
<summary>Generated <code>summary.json</code></summary>

```json
{
  "run_label": "standard-greeting",
  "scenario": "Add greeting feature",
  "preset": "standard",
  "model": "claude-sonnet-4-20250514",
  "timestamp": "2026-05-01T16:05:18Z",
  "step_count": 4,
  "tokens": {
    "total_input": 68680,
    "total_output": 22000,
    "total": 90680,
    "cache_read": 44700,
    "cache_creation": 23980
  },
  "steps": [
    { "command": "speckit.specify", "input": 12480, "output": 3200, "total": 15680 },
    { "command": "speckit.plan", "input": 15600, "output": 4100, "total": 19700 },
    { "command": "speckit.tasks", "input": 18200, "output": 5800, "total": 24000 },
    { "command": "speckit.implement", "input": 22400, "output": 8900, "total": 31300 }
  ]
}
```

</details>

---

## Hooks

The extension registers optional hooks that prompt after each SDD step:

| Hook | Trigger | Prompt |
|------|---------|--------|
| `after_specify` | After specification generation | *Capture token metrics from specification?* |
| `after_plan` | After implementation planning | *Capture token metrics from planning?* |
| `after_tasks` | After task generation | *Capture token metrics from task generation?* |
| `after_implement` | After implementation | *Capture token metrics from implementation?* |

All hooks are optional — they prompt before running and can be skipped.

---

## Data Storage

All captured data lives under `.specify/token-analysis/`:

```
.specify/token-analysis/
├── runs/
│   └── {run-label}/
│       ├── metadata.json
│       ├── steps/
│       │   ├── specify.json
│       │   ├── plan.json
│       │   ├── tasks.json
│       │   └── implement.json
│       ├── summary.json
│       └── report.md
├── baselines/
│   └── {name}.json
└── comparisons/
    └── {baseline}-vs-{variant}.md
```

---

## Requirements

- spec-kit >= 0.2.0
- `jq` (recommended for clean JSON output; scripts fall back to grep/sed without it)
- bash or PowerShell

## License

MIT
