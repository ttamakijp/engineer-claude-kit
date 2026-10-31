#!/usr/bin/env pwsh
# build-rules.ps1
# Build Claude rules from source/rules/ to dist/.claude/rules/
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001 section I and ADR-0003 section C.
#
# The dist dir is a build output, not an accumulator: a rule that stops being
# emitted (audience no longer includes 'claude', a renamed id, a deleted source
# file) must disappear from it. apply deploys every *.md it finds there, so a
# leftover copy keeps loading into every session long after the source said to
# stop shipping it -- which is how local-llm-fallback.md reached ~/.claude/rules/
# despite 'audience: [kit]', inflating the always-loaded surface by 1,568 B.

[CmdletBinding()]
param(
    [string]$SourceDir,
    [string]$DistDir,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty while a param default is being evaluated under
# "powershell -File <script>", which made both defaults throw on Join-Path and
# left the script runnable only with -SourceDir and -DistDir spelled out. The
# defaults are resolved here instead, where $PSScriptRoot is populated; the
# fallback chain is the one the test suite already uses.
$here = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}
if (-not $SourceDir) { $SourceDir = Join-Path (Join-Path (Join-Path $here "..") "source") "rules" }
if (-not $DistDir) { $DistDir = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "dist") ".claude") "rules" }

# UTF-8 (no BOM) file I/O helpers. Source rules contain Japanese, so reading them
# with the host default codepage (CP932 on PS 5.1) would mojibake every rule.
# See ADR-0003 section C.
. (Join-Path (Join-Path $here "lib") "encoding-helper.ps1")

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
    #
    # Frontmatter contract (ADR-0015 step 1). Only two keys are consumed here:
    #   id        -> dist filename (<id>.md)
    #   audience  -> build filter; a rule is emitted only when it includes 'claude'
    # Everything else is passed through verbatim for Claude Code to interpret, and
    # Claude Code reads exactly one key of its own: 'paths' (glob patterns that
    # scope the rule to matching files; absent means load unconditionally). Any
    # other key is ignored by Claude Code without an error, which is why the legacy
    # applyTo / priority / tags / title / description keys were removed rather than
    # translated. A 'paths' block list parses to an empty hashtable below (list
    # items do not match the 'subkey: value' pattern); that is harmless because
    # nothing in this script reads it and the block is copied through untouched.
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

    $content = Read-Utf8NoBom -Path $SourceFile
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
    Write-Utf8NoBom -Path $outFile -Content $content
    Write-Host "[build] $SourceFile -> $outFile"
    return $outFile
}

function Remove-StaleRuleOutputs {
    # Delete the *.md files in the dist dir that this build did not produce.
    #
    # Scoped to *.md and never recursive, on purpose. This script owns exactly
    # the "<id>.md" files it writes, so that set is the whole of what it may
    # delete. -DistDir is caller-supplied (the test suite points it at a temp
    # dir), and a wholesale "Remove-Item -Recurse -Force $DistDir" would turn a
    # mistyped argument into data loss while fixing nothing pruning does not.
    param(
        [Parameter(Mandatory)][string]$DistDirPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BuiltFiles,
        [switch]$IsDryRun
    )

    if (-not (Test-Path -LiteralPath $DistDirPath)) { return @() }

    # Compare on leaf names: $BuiltFiles holds Join-Path results, which can
    # differ from Get-ChildItem's paths in separator or casing.
    $keep = @{}
    foreach ($p in $BuiltFiles) { $keep[(Split-Path -Leaf $p).ToLowerInvariant()] = $true }

    $removed = @()
    foreach ($file in (Get-ChildItem -LiteralPath $DistDirPath -Filter "*.md" -File)) {
        if ($keep.ContainsKey($file.Name.ToLowerInvariant())) { continue }
        if ($IsDryRun) {
            Write-Host "[dry-run] remove stale $($file.FullName)"
        } else {
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Host "[clean] removed stale $($file.FullName)"
        }
        $removed += $file.FullName
    }
    return $removed
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

# @() keeps a single removal a one-element array instead of a bare string.
$stale = @(Remove-StaleRuleOutputs -DistDirPath $DistDir -BuiltFiles $built -IsDryRun:$DryRun)

Write-Host ""
Write-Host "Built $($built.Count) rule(s) of $($srcFiles.Count) source file(s)."
if ($stale.Count -gt 0) {
    $verb = if ($DryRun) { "Would remove" } else { "Removed" }
    Write-Host "$verb $($stale.Count) stale rule(s) no longer produced by this build."
}
