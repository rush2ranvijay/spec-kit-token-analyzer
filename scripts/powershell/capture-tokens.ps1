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

    [string]$File
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
    $RawInput = $input | Out-String
}

# Parse JSON
try {
    $parsed = $RawInput | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse JSON input: $_"
    exit 1
}

# Extract token fields - handle nested structures
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

$InputTokens = [int](Find-Field $parsed "input_tokens")
$OutputTokens = [int](Find-Field $parsed "output_tokens")
$CacheRead = [int](Find-Field $parsed "cache_read_input_tokens")
$CacheCreation = [int](Find-Field $parsed "cache_creation_input_tokens")
$Model = Find-StringField $parsed "model"
$StopReason = Find-StringField $parsed "stop_reason"
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
