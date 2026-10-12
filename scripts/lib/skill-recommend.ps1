#requires -Version 5.1
# skill-recommend.ps1
# Provides: project-type detection and a one-shot relevant-skill hint, printed at
#           the end of a Project-mode apply run.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 section C.
#
# Functions:
#   Read-SkillRecommendConfig - parse config/recommended-skills.yaml
#   Test-ProjectType          - does a project root match a type's detect globs
#   Get-RecommendedSkills     - skills relevant to one project
#   Write-SkillRecommendation - render the hint block
#
# Why this replaced a rule:
# project-skill-recommend.md asked Claude to check a marker file, resolve the git
# root, glob for build files, cross-check two skill directories and then decide
# whether to speak -- on the first turn of every session, with a silent fallback
# when any step was skipped. None of that is a judgement call, and nothing could
# tell whether it had run. Apply already knows the project root and runs exactly
# once, so the suggestion belongs there and the rule is deleted outright.

function Read-SkillRecommendConfig {
    # Parse the project_types block of recommended-skills.yaml into a hashtable:
    #   @{ android = @{ Detect = @('gradlew', ...); Recommend = @('android-build') } }
    #
    # Deliberately minimal: two nesting levels and inline list items are all the
    # schema uses. An absent or unreadable file yields an empty hashtable so the
    # caller simply recommends nothing.
    param([Parameter(Mandatory)][string]$Path)

    $types = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $types }

    $text = ''
    try { $text = [System.IO.File]::ReadAllText($Path) } catch { return $types }

    $inProjectTypes = $false
    $currentType = $null
    $currentList = $null

    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*#') { continue }
        if ($line.Trim() -eq '') { continue }

        # Top-level key.
        if ($line -match '^([A-Za-z_][A-Za-z0-9_-]*)\s*:') {
            $inProjectTypes = ($Matches[1] -eq 'project_types')
            $currentType = $null
            $currentList = $null
            continue
        }
        if (-not $inProjectTypes) { continue }

        # "  <type>:" -- two-space indent.
        if ($line -match '^\s{2}([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*$') {
            $currentType = $Matches[1]
            $types[$currentType] = @{ Detect = @(); Recommend = @() }
            $currentList = $null
            continue
        }
        if (-not $currentType) { continue }

        # "    detect:" / "    recommend:" possibly with an inline empty list.
        if ($line -match '^\s{4}(detect|recommend)\s*:\s*(.*)$') {
            $currentList = $Matches[1]
            $inline = $Matches[2].Trim()
            # "recommend: []" (with an optional trailing comment) means none.
            if ($inline -match '^\[\s*\]') { $currentList = $null }
            continue
        }

        # "      - value" list item.
        if ($currentList -and $line -match '^\s{6}-\s*(.+)$') {
            $value = $Matches[1].Trim()
            # Strip a trailing comment, then quotes.
            $value = ($value -replace '\s+#.*$', '').Trim().Trim('"').Trim("'")
            if (-not $value) { continue }
            if ($currentList -eq 'detect') {
                $types[$currentType].Detect += $value
            } else {
                $types[$currentType].Recommend += $value
            }
        }
    }
    return $types
}

function Test-ProjectType {
    # True when any detect glob matches an entry at the project root. Matching is
    # top-level only, mirroring the "ls gradlew" check the rule described: a
    # package.json buried in node_modules must not make this a Node project.
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DetectPatterns
    )

    foreach ($pattern in $DetectPatterns) {
        $hit = @(Get-ChildItem -LiteralPath $ProjectRoot -Filter $pattern -Force -ErrorAction SilentlyContinue)
        if ($hit.Count -gt 0) { return $true }
    }
    return $false
}

function Get-RecommendedSkills {
    # Skills relevant to $ProjectRoot: the project matches the type and the skill
    # exists in the global library. Multiple matching types are all reported
    # (hybrid repos are common).
    #
    # -OnlyMissing additionally drops skills the project already has. Apply does
    # NOT use it, because by the time apply reaches this point it has deployed
    # every skill into <project>/.claude/skills/ -- so "missing" is always empty
    # there and an "install this" hint would be false. The switch stays for
    # callers that inspect a project apply has not touched.
    #
    # Returns an array of PSCustomObject (Type, Skill), empty when there is
    # nothing to say.
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [string]$GlobalSkillsDir,
        [switch]$OnlyMissing
    )

    if (-not $GlobalSkillsDir) {
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        $GlobalSkillsDir = Join-Path (Join-Path $userHome ".claude") "skills"
    }
    $projectSkillsDir = Join-Path (Join-Path $ProjectRoot ".claude") "skills"

    $out = @()
    $types = Read-SkillRecommendConfig -Path $ConfigPath
    foreach ($typeName in ($types.Keys | Sort-Object)) {
        $spec = $types[$typeName]
        if (@($spec.Recommend).Count -eq 0) { continue }
        if (-not (Test-ProjectType -ProjectRoot $ProjectRoot -DetectPatterns $spec.Detect)) { continue }

        foreach ($skill in $spec.Recommend) {
            if (-not (Test-Path -LiteralPath (Join-Path $GlobalSkillsDir $skill))) { continue }
            if ($OnlyMissing -and (Test-Path -LiteralPath (Join-Path $projectSkillsDir $skill))) { continue }
            $out += [PSCustomObject]@{ Type = $typeName; Skill = $skill }
        }
    }
    return $out
}

function Write-SkillRecommendation {
    # Print the suggestion block. Says nothing when there is nothing to report.
    #
    # The Where-Object is not decoration: a function that returns an empty @()
    # emits nothing, so the call site's argument becomes $null, and @($null) is a
    # one-element array holding $null. Without the filter that renders as a hint
    # with blank fields.
    param($Recommendations)

    $items = @($Recommendations | Where-Object { $_ -and $_.Skill })
    if ($items.Count -eq 0) { return }

    $types = ($items | ForEach-Object { $_.Type } | Sort-Object -Unique) -join ', '
    $skills = ($items | ForEach-Object { $_.Skill } | Sort-Object -Unique) -join ', '
    Write-Host ""
    Write-Host "[hint] Detected project type(s): $types"
    Write-Host "       Relevant skills available here: $skills"
}
