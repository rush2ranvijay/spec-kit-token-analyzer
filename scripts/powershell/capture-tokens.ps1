<#
.SYNOPSIS
    Parse CLI JSON response for token fields.
.DESCRIPTION
    Reads CLI JSON response output, extracts token metrics, and writes per-step JSON
    to .specify/token-analysis/runs/{label}/steps/
.PARAMETER RunLabel
    The run label identifier.
.PARAMETER Step
    The command/step name (e.g., "specify", "plan").
.PARAMETER Json
    Output in JSON format.
.PARAMETER File
    Path to CLI response JSON file. If omitted, reads from stdin.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$RunLabel,

    [Parameter(Mandatory=$true)]
    [string]$Step,

    [switch]$Json,

    [string]$File,

    [Parameter(ValueFromPipeline=$true)]
    [string]$PipelineInput
)

$ErrorActionPreference = "Stop"

# Read input
if ($File) {
    if (-not (Test-Path $File)) {
        Write-Error "File not found: $File"
        exit 1
    }
    $RawInput = Get-Content -Raw $File
} else {
    if ($PipelineInput) {
        $RawInput = $PipelineInput
    } else {
        $RawInput = @($input) -join "`n"
    }
}

# Parse JSON
try {
    $parsed = $RawInput | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse JSON input: $_"
    exit 1
}

# Extract token fields - handle nested structures
# Supports three provider formats:
#   - Anthropic/Claude: input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens
#   - OpenAI/Copilot:   prompt_tokens, completion_tokens, total_tokens
#   - Google Gemini:    promptTokenCount, candidatesTokenCount, totalTokenCount, cachedContentTokenCount

function Find-Field {
    param($obj, $fieldName)
    if ($null -eq $obj) { return 0 }
    if ($obj.PSObject.Properties[$fieldName]) { return $obj.$fieldName }
    foreach ($prop in $obj.PSObject.Properties) {
        if ($prop.Value -is [PSCustomObject]) {
            $result = Find-Field $prop.Value $fieldName
            if ($result -ne 0) { return $result }
        }
    }
    return 0
}

function Find-StringField {
    param($obj, $fieldName)
    if ($null -eq $obj) { return "unknown" }
    if ($obj.PSObject.Properties[$fieldName]) { return [string]$obj.$fieldName }
    foreach ($prop in $obj.PSObject.Properties) {
        if ($prop.Value -is [PSCustomObject]) {
            $result = Find-StringField $prop.Value $fieldName
            if ($result -ne "unknown") { return $result }
        }
    }
    return "unknown"
}

function Find-FieldMulti {
    param($obj, [string[]]$fieldNames)
    foreach ($name in $fieldNames) {
        $val = [int](Find-Field $obj $name)
        if ($val -ne 0) { return $val }
    }
    return 0
}

function Find-StringFieldMulti {
    param($obj, [string[]]$fieldNames)
    foreach ($name in $fieldNames) {
        $val = Find-StringField $obj $name
        if ($val -ne "unknown" -and $val -ne "") { return $val }
    }
    return "unknown"
}

# Input tokens:  Claude input_tokens -> OpenAI prompt_tokens -> Gemini promptTokenCount
$InputTokens = [int](Find-FieldMulti $parsed @("input_tokens", "prompt_tokens", "promptTokenCount"))

# Output tokens: Claude output_tokens -> OpenAI completion_tokens -> Gemini candidatesTokenCount
$OutputTokens = [int](Find-FieldMulti $parsed @("output_tokens", "completion_tokens", "candidatesTokenCount"))

# Cache read:    Claude cache_read_input_tokens -> Gemini cachedContentTokenCount
$CacheRead = [int](Find-FieldMulti $parsed @("cache_read_input_tokens", "cachedContentTokenCount"))

# Cache creation: Claude only
$CacheCreation = [int](Find-Field $parsed "cache_creation_input_tokens")

# Model: universal "model" -> Gemini "modelVersion"
$Model = Find-StringFieldMulti $parsed @("model", "modelVersion")

# Stop reason: Claude stop_reason -> OpenAI finish_reason -> Gemini finishReason
$StopReason = Find-StringFieldMulti $parsed @("stop_reason", "finish_reason", "finishReason")
$TotalTokens = $InputTokens + $OutputTokens

# Ensure output directory exists
$DataDir = ".specify/token-analysis/runs/$RunLabel/steps"
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Build output object
$output = [ordered]@{
    command      = "speckit.$Step"
    model        = $Model
    timestamp    = $Timestamp
    stop_reason  = $StopReason
    tokens       = [ordered]@{
        input          = $InputTokens
        output         = $OutputTokens
        total          = $TotalTokens
        cache_read     = $CacheRead
        cache_creation = $CacheCreation
    }
}

$OutputPath = Join-Path $DataDir "$Step.json"
$output | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8

if ($Json) {
    $output | ConvertTo-Json -Depth 5
} else {
    Write-Host "Captured tokens for ${Step}:"
    Write-Host "  Input:          $InputTokens"
    Write-Host "  Output:         $OutputTokens"
    Write-Host "  Total:          $TotalTokens"
    Write-Host "  Cache read:     $CacheRead"
    Write-Host "  Cache creation: $CacheCreation"
    Write-Host "  Model:          $Model"
    Write-Host "  Saved to:       $OutputPath"
}
