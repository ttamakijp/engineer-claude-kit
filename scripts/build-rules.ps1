#!/usr/bin/env pwsh
# build-rules.ps1
# Build Claude rules from source/rules/ to dist/.claude/rules/
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001 section I and ADR-0003 section C.

[CmdletBinding()]
param(
    [string]$SourceDir = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "source") "rules"),
    [string]$DistDir = (Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "dist") ".claude") "rules"),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Parse-Frontmatter {
    param([string]$Content)

    # Frontmatter delimiter is "---" on the first line and again later
    # Returns a hashtable for the frontmatter and the body string.

    if ($Content -notmatch '^---\s*\r?\n') {
        return @{ Frontmatter = @{}; Body = $Content }
    }

    # Strip leading "---\n", find the next "---" line
    $lines = $Content -split '\r?\n'
    if ($lines[0].Trim() -ne '---') {
        return @{ Frontmatter = @{}; Body = $Content }
    }

    $fmLines = @()
    $bodyStart = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') {
            $bodyStart = $i + 1
            break
        }
        $fmLines += $lines[$i]
    }
    if ($bodyStart -lt 0) {
        return @{ Frontmatter = @{}; Body = $Content }
    }

    # Very minimal YAML parser:
    #   key: value
    #   key: [a, b, c]
    #   key:
    #     subkey: subvalue
    # No nested arrays, no anchors, no multi-line scalars (good enough for our schema).
    $fm = @{}
    $currentKey = $null
    foreach ($line in $fmLines) {
        if ($line -match '^\s*#') { continue }
        if ($line.Trim() -eq '') { continue }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val -eq '') {
                # Block scalar follows; for now stub it as empty hashtable
                $fm[$key] = @{}
                $currentKey = $key
            } elseif ($val -match '^\[(.*)\]$') {
                # Inline list
                $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") }
                $fm[$key] = $items
                $currentKey = $null
            } else {
                $fm[$key] = $val.Trim('"').Trim("'")
                $currentKey = $null
            }
        } elseif ($line -match '^\s+([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$' -and $currentKey -ne $null) {
            $subkey = $Matches[1]
            $subval = $Matches[2].Trim()
            $fm[$currentKey][$subkey] = $subval.Trim('"').Trim("'")
        }
    }

    $body = ($lines[$bodyStart..($lines.Count - 1)] -join "`n")
    return @{ Frontmatter = $fm; Body = $body }
}

function Test-AudienceContainsClaude {
    param($Audience)

    if ($null -eq $Audience) { return $false }
    if ($Audience -is [string]) {
        return ($Audience -eq 'claude' -or $Audience -eq '[claude]')
    }
    if ($Audience -is [array]) {
        return ($Audience -contains 'claude')
    }
    return $false
}

function Build-Rule {
    param(
        [string]$SourceFile,
        [string]$DistDirPath,
        [switch]$IsDryRun
    )

    $content = Get-Content -Raw -LiteralPath $SourceFile
    $parsed = Parse-Frontmatter -Content $content

    $id = $parsed.Frontmatter.id
    if (-not $id) {
        Write-Warning "Skipping $SourceFile : frontmatter has no 'id' key"
        return $null
    }
    if (-not (Test-AudienceContainsClaude -Audience $parsed.Frontmatter.audience)) {
        Write-Verbose "Skipping $SourceFile : audience does not include 'claude'"
        return $null
    }

    $outFile = Join-Path $DistDirPath "$id.md"
    if ($IsDryRun) {
        Write-Host "[dry-run] $SourceFile -> $outFile"
        return $outFile
    }

    if (-not (Test-Path $DistDirPath)) {
        New-Item -ItemType Directory -Force -Path $DistDirPath | Out-Null
    }

    # Reassemble the file: keep frontmatter as-is, append body.
    # For simplicity, write the original content (frontmatter included).
    Set-Content -LiteralPath $outFile -Value $content -Encoding UTF8 -NoNewline
    Write-Host "[build] $SourceFile -> $outFile"
    return $outFile
}

# Main
$resolvedSource = (Resolve-Path -LiteralPath $SourceDir -ErrorAction Stop).Path
Write-Host "Source dir: $resolvedSource"
Write-Host "Dist dir:   $DistDir"
if ($DryRun) { Write-Host "Mode: dry-run" }

$srcFiles = Get-ChildItem -LiteralPath $resolvedSource -Recurse -Filter "*.md" -File
if ($srcFiles.Count -eq 0) {
    Write-Warning "No source rule files found in $resolvedSource"
    exit 0
}

$built = @()
foreach ($f in $srcFiles) {
    $out = Build-Rule -SourceFile $f.FullName -DistDirPath $DistDir -IsDryRun:$DryRun
    if ($out) { $built += $out }
}

Write-Host ""
Write-Host "Built $($built.Count) rule(s) of $($srcFiles.Count) source file(s)."
