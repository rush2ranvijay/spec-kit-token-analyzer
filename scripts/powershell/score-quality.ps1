<#
.SYNOPSIS
    Analyze an artifact file against expected sections and compute quality score.
.PARAMETER Command
    The spec-kit command that produced this artifact.
.PARAMETER Json
    Output in JSON format.
.PARAMETER Path
    Path to the artifact file to analyze.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Command,

    [switch]$Json,

    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

# Expected sections per command
$expectedSections = switch ($Command) {
    "specify"      { @("user-stories", "acceptance-criteria", "requirements", "assumptions") }
    "plan"         { @("architecture", "components", "data-model", "implementation-approach") }
    "tasks"        { @("tasks", "dependencies") }
    "implement"    { @("implementation") }
    "checklist"    { @("checklist", "verification") }
    "clarify"      { @("questions", "clarifications") }
    "constitution" { @("principles", "guidelines", "standards") }
    "analyze"      { @("analysis", "findings", "recommendations") }
    default        { @("content") }
}

$content = Get-Content -Raw $Path
$lines = Get-Content $Path
$artifactSize = $content.Length
$artifactLines = $lines.Count

# section_completeness
$foundCount = 0
$foundSections = @()
$missingSections = @()

foreach ($section in $expectedSections) {
    $pattern = $section -replace "-", "[ -]"
    if ($content -match "(?i)$pattern") {
        $foundCount++
        $foundSections += $section
    } else {
        $missingSections += $section
    }
}

$expectedCount = $expectedSections.Count
$sectionCompleteness = if ($expectedCount -gt 0) { [math]::Round($foundCount / $expectedCount, 2) } else { 1.0 }

# content_depth
$h2Count = ($lines | Where-Object { $_ -match "^## " }).Count
if ($h2Count -gt 0) {
    $avgSectionSize = [math]::Floor($artifactSize / $h2Count)
    $contentDepth = if ($avgSectionSize -ge 500) { 1.0 }
                    elseif ($avgSectionSize -ge 200) { 0.75 }
                    elseif ($avgSectionSize -ge 100) { 0.50 }
                    else { 0.25 }
} else {
    $contentDepth = if ($artifactSize -ge 1000) { 0.75 }
                    elseif ($artifactSize -ge 500) { 0.50 }
                    else { 0.25 }
}

# cross_reference_accuracy
$refCount = 0
foreach ($ref in @("spec.md", "plan.md", "tasks.md", "checklist.md", "constitution.md", "data-model")) {
    if ($content -match [regex]::Escape($ref)) { $refCount++ }
}

$expectedRefs = switch ($Command) {
    "specify" { 0 }
    "plan" { 1 }
    "tasks" { 2 }
    "implement" { 2 }
    default { 0 }
}

$crossRef = if ($expectedRefs -eq 0) { 1.0 }
            elseif ($refCount -ge $expectedRefs) { 1.0 }
            else { [math]::Round($refCount / $expectedRefs, 2) }

# actionability
$checkboxCount = ($lines | Where-Object { $_ -match "\- \[" }).Count
$numberedList = ($lines | Where-Object { $_ -match "^\d+\." }).Count
$actionMarkers = $checkboxCount + $numberedList

$actionability = if ($actionMarkers -ge 10) { 1.0 }
                 elseif ($actionMarkers -ge 5) { 0.75 }
                 elseif ($actionMarkers -ge 2) { 0.50 }
                 else { 0.25 }

# format_compliance
$hasH1 = ($lines | Where-Object { $_ -match "^# " }).Count -ge 1
$hasH2 = $h2Count -ge 1
$hasLength = $artifactLines -ge 10

$formatPoints = [int]$hasH1 + [int]$hasH2 + [int]$hasLength
$formatCompliance = if ($formatPoints -ge 3) { 1.0 }
                    elseif ($formatPoints -ge 2) { 0.75 }
                    elseif ($formatPoints -ge 1) { 0.50 }
                    else { 0.25 }

# Overall quality score
$qualityScore = [math]::Round(
    $sectionCompleteness * 0.3 +
    $contentDepth * 0.25 +
    $crossRef * 0.2 +
    $actionability * 0.15 +
    $formatCompliance * 0.1, 2)

$meetsThreshold = ($qualityScore -ge 0.75) -and
                  ($sectionCompleteness -ge 0.5) -and
                  ($contentDepth -ge 0.5) -and
                  ($crossRef -ge 0.5) -and
                  ($actionability -ge 0.5) -and
                  ($formatCompliance -ge 0.5)

$output = [ordered]@{
    command                  = $Command
    artifact                 = $Path
    artifact_size_bytes      = $artifactSize
    scores                   = [ordered]@{
        section_completeness      = $sectionCompleteness
        content_depth             = $contentDepth
        cross_reference_accuracy  = $crossRef
        actionability             = $actionability
        format_compliance         = $formatCompliance
    }
    quality_score            = $qualityScore
    meets_minimum_threshold  = $meetsThreshold
    sections_found           = $foundCount
    sections_expected        = $expectedCount
}

if ($Json) {
    $output | ConvertTo-Json -Depth 5
} else {
    Write-Host "Quality Score: $Path"
    Write-Host "  Command:               $Command"
    Write-Host "  Section completeness:  $sectionCompleteness ($foundCount/$expectedCount)"
    Write-Host "  Content depth:         $contentDepth"
    Write-Host "  Cross-ref accuracy:    $crossRef"
    Write-Host "  Actionability:         $actionability"
    Write-Host "  Format compliance:     $formatCompliance"
    Write-Host "  ────────────────────────────"
    Write-Host "  Overall quality:       $qualityScore"
    Write-Host "  Meets threshold:       $meetsThreshold"
}
