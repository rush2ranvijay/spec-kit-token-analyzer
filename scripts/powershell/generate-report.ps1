<#
.SYNOPSIS
    Aggregate step JSONs for a run into summary.json and markdown report.
.PARAMETER RunLabel
    The run label to generate a report for.
.PARAMETER Json
    Output summary as JSON instead of markdown.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$RunLabel,

    [switch]$Json
)

$ErrorActionPreference = "Stop"

$RunDir = ".specify/token-analysis/runs/$RunLabel"
$StepsDir = "$RunDir/steps"

if (-not (Test-Path $StepsDir)) {
    Write-Error "No steps found at $StepsDir"
    exit 1
}

# Aggregate step data
$totalInput = 0
$totalOutput = 0
$totalTokens = 0
$totalCacheRead = 0
$totalCacheCreation = 0
$stepCount = 0
$stepsData = @()
$model = "unknown"

foreach ($stepFile in Get-ChildItem -Path $StepsDir -Filter "*.json") {
    $step = Get-Content -Raw $stepFile.FullName | ConvertFrom-Json
    $stepCount++

    $sInput = [int]$step.tokens.input
    $sOutput = [int]$step.tokens.output
    $sTotal = [int]$step.tokens.total
    $sCacheRead = [int]$step.tokens.cache_read
    $sCacheCreation = [int]$step.tokens.cache_creation

    $totalInput += $sInput
    $totalOutput += $sOutput
    $totalTokens += $sTotal
    $totalCacheRead += $sCacheRead
    $totalCacheCreation += $sCacheCreation
    $model = $step.model

    $stepsData += [ordered]@{
        command = $step.command
        input   = $sInput
        output  = $sOutput
        total   = $sTotal
    }
}

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Read metadata
$scenario = ""
$preset = "standard"
$metadataPath = "$RunDir/metadata.json"
if (Test-Path $metadataPath) {
    $metadata = Get-Content -Raw $metadataPath | ConvertFrom-Json
    $scenario = $metadata.scenario
    $preset = $metadata.preset
}

# Write summary.json
$summary = [ordered]@{
    run_label  = $RunLabel
    scenario   = $scenario
    preset     = $preset
    model      = $model
    timestamp  = $timestamp
    step_count = $stepCount
    tokens     = [ordered]@{
        total_input    = $totalInput
        total_output   = $totalOutput
        total          = $totalTokens
        cache_read     = $totalCacheRead
        cache_creation = $totalCacheCreation
    }
    steps      = $stepsData
}

$summaryPath = "$RunDir/summary.json"
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8

# Generate markdown report
$reportLines = @(
    "# Token Analysis Report: $RunLabel",
    "",
    "Generated: $timestamp",
    "Scenario: $scenario",
    "Preset: $preset",
    "Model: $model",
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "|--------|-------|",
    "| Steps captured | $stepCount |",
    "| Total input tokens | $totalInput |",
    "| Total output tokens | $totalOutput |",
    "| Total tokens | $totalTokens |",
    "| Cache read tokens | $totalCacheRead |",
    "| Cache creation tokens | $totalCacheCreation |",
    "",
    "## Per-Step Breakdown",
    "",
    "| Command | Input | Output | Total |",
    "|---------|-------|--------|-------|"
)

foreach ($s in $stepsData) {
    $reportLines += "| $($s.command) | $($s.input) | $($s.output) | $($s.total) |"
}

$reportPath = "$RunDir/report.md"
$reportLines | Set-Content -Path $reportPath -Encoding UTF8

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
} else {
    Get-Content $reportPath
}
