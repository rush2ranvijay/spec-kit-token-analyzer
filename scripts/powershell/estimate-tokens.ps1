<#
.SYNOPSIS
    Estimate token count from a markdown file using character heuristic.
.DESCRIPTION
    Uses 1 token ≈ 4 chars heuristic. Breaks down by markdown section (H2 headers).
.PARAMETER Json
    Output in JSON format.
.PARAMETER Path
    Path to the markdown file to analyze.
#>
param(
    [switch]$Json,

    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

$content = Get-Content -Path $Path
$totalChars = 0
$totalLines = $content.Count
$sections = @()
$currentSection = "(preamble)"
$currentChars = 0

foreach ($line in $content) {
    $totalChars += $line.Length

    if ($line -match "^## (.+)") {
        # Save previous section
        $sections += [ordered]@{
            section          = $currentSection
            chars            = $currentChars
            estimated_tokens = [math]::Ceiling($currentChars / 4)
        }
        $currentSection = $Matches[1]
        $currentChars = 0
    } else {
        $currentChars += $line.Length
    }
}

# Save last section
$sections += [ordered]@{
    section          = $currentSection
    chars            = $currentChars
    estimated_tokens = [math]::Ceiling($currentChars / 4)
}

$totalEstimated = [math]::Ceiling($totalChars / 4)

$output = [ordered]@{
    file                   = $Path
    total_chars            = $totalChars
    total_lines            = $totalLines
    total_estimated_tokens = $totalEstimated
    sections               = $sections
}

if ($Json) {
    $output | ConvertTo-Json -Depth 5
} else {
    Write-Host "Token Estimate: $Path"
    Write-Host "  Total characters: $totalChars"
    Write-Host "  Total lines:      $totalLines"
    Write-Host "  Estimated tokens: $totalEstimated"
    Write-Host ""
    Write-Host "  Breakdown by section:"
    foreach ($s in $sections) {
        Write-Host ("    {0,-40} {1} tokens" -f $s.section, $s.estimated_tokens)
    }
}
