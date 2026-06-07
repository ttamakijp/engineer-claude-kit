#!/usr/bin/env pwsh
# apply-claude-kit.ps1
# Apply engineer-claude-kit templates to ~/.claude (global) or <project>/.claude (project).
# Resolves placeholders ({{role:main}}, {{role:small-fast}}) from config/models.yaml.
# ASCII only (no Japanese in code, comments, or strings).
# See ADR-0001 section I, ADR-0003 section B/C, ADR-0004 section B/D.

[CmdletBinding(DefaultParameterSetName='Global')]
param(
    [Parameter(ParameterSetName='Global')]
    [switch]$Global,

    [Parameter(ParameterSetName='Project', Mandatory=$true)]
    [string]$Project,

    [switch]$DryRun,

    [switch]$AllowElevated,

    # Default resolved in the body: referencing $PSScriptRoot in a param default
    # is unreliable under Windows PowerShell 5.1 when parameter sets are present.
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"

# Fail-fast if running as Administrator (see ADR-0008). Escape hatch: -AllowElevated.
. (Join-Path (Join-Path $PSScriptRoot "lib") "privilege-check.ps1")
Assert-NonElevated -AllowElevated:$AllowElevated

if (-not $KitRoot) {
    $KitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

# --- minimal YAML reader for our config schema ---

function Read-ConfigYaml {
    param([string]$Path)

    # Returns a hashtable. Supports:
    #   key: value
    #   key:
    #     subkey: value
    #     subkey:
    #       nestedkey: value
    #   key: [a, b, c]
    # Indentation is 2 spaces. Comments start with #. No anchors, no multi-line scalars.

    $content = Get-Content -LiteralPath $Path -Raw
    $lines = $content -split "`r?`n"
    $root = @{}
    $stack = @(@{ Indent = -1; Map = $root })

    foreach ($rawLine in $lines) {
        if ($rawLine -match '^\s*#') { continue }
        if ($rawLine -match '^\s*$') { continue }

        # Remove trailing comments (very simple - does not handle # inside quotes)
        $line = $rawLine -replace '\s+#.*$', ''

        # Indent count (spaces only)
        $indent = 0
        while ($indent -lt $line.Length -and $line[$indent] -eq ' ') { $indent++ }

        # Pop stack until parent indent < current indent
        while ($stack.Count -gt 1 -and $stack[-1].Indent -ge $indent) {
            $stack = $stack[0..($stack.Count - 2)]
        }
        $current = $stack[-1].Map

        $body = $line.Substring($indent)
        if ($body -match '^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()

            if ($val -eq '') {
                $child = @{}
                $current[$key] = $child
                $stack += @{ Indent = $indent; Map = $child }
            } elseif ($val -match '^\[(.*)\]$') {
                $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") }
                $current[$key] = $items
            } else {
                $clean = $val.Trim('"').Trim("'")
                $current[$key] = $clean
            }
        } elseif ($body -match '^-\s+(.*)$') {
            # List item under a key whose value started as block.
            # Phase 2.2 Q only consumes models.yaml (maps only), so list items are
            # stored as plain strings under a "_list" key for any future caller.
            if (-not $current.ContainsKey('_list')) { $current['_list'] = @() }
            $current['_list'] += $Matches[1].Trim()
        }
    }

    return $root
}

# --- model role resolution ---

function Resolve-ModelId {
    param(
        [hashtable]$ModelsConfig,
        [string]$Role
    )

    $models = $ModelsConfig['models']
    if ($null -eq $models) {
        throw "config/models.yaml: missing 'models' key"
    }

    if ($models.ContainsKey($Role)) {
        $id = $models[$Role]['id']
        if (-not $id) {
            throw "config/models.yaml: model '$Role' has no 'id' field"
        }
        return $id
    }

    # Lookup via roles.<role>.role-of
    $roles = $ModelsConfig['roles']
    if ($null -ne $roles -and $roles.ContainsKey($Role)) {
        $roleOf = $roles[$Role]['role-of']
        if ($roleOf) {
            return (Resolve-ModelId -ModelsConfig $ModelsConfig -Role $roleOf)
        }
    }

    throw "config/models.yaml: cannot resolve model role '$Role'"
}

# --- template substitution ---

function Invoke-TemplateSubstitution {
    param(
        [string]$TemplateContent,
        [hashtable]$ModelsConfig
    )

    $result = $TemplateContent

    # Find all {{role:<name>}} placeholders. {{user.*}} placeholders are reserved
    # for a future phase and intentionally left untouched here.
    $pattern = '\{\{role:([a-z][a-z0-9-]*)\}\}'
    $placeholderMatches = [System.Text.RegularExpressions.Regex]::Matches($result, $pattern)
    foreach ($m in $placeholderMatches) {
        $role = $m.Groups[1].Value
        $id = Resolve-ModelId -ModelsConfig $ModelsConfig -Role $role
        $result = $result -replace ('\{\{role:' + [regex]::Escape($role) + '\}\}'), $id
    }

    return $result
}

# --- deployment ---

function Copy-Template {
    param(
        [string]$SourceFile,
        [string]$DestFile,
        [hashtable]$ModelsConfig,
        [switch]$IsDryRun
    )

    $content = Get-Content -LiteralPath $SourceFile -Raw
    $rendered = Invoke-TemplateSubstitution -TemplateContent $content -ModelsConfig $ModelsConfig

    if ($IsDryRun) {
        Write-Host "[dry-run] $SourceFile -> $DestFile"
        return $DestFile
    }

    $destDir = Split-Path -Parent $DestFile
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    # UTF-8 without BOM; -NoNewline avoids Set-Content appending a trailing newline.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($DestFile, $rendered, $utf8NoBom)
    Write-Host "[apply] $SourceFile -> $DestFile"
    return $DestFile
}

# --- marker file ---

function Write-AppliedMarker {
    param(
        [string]$TargetRoot,
        [string]$Mode,
        [array]$AppliedFiles
    )

    $markerPath = Join-Path $TargetRoot ".engineer-claude-kit-applied"
    $marker = [ordered]@{
        version = $ScriptVersion
        mode = $Mode
        applied_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
        applied_files = $AppliedFiles
    } | ConvertTo-Json -Depth 5
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($markerPath, $marker, $utf8NoBom)
    Write-Host "[marker] $markerPath"
}

# --- Main ---

$configPath = Join-Path (Join-Path $KitRoot "config") "models.yaml"
if (-not (Test-Path $configPath)) {
    throw "config/models.yaml not found at: $configPath"
}
Write-Host "Loading $configPath"
$modelsConfig = Read-ConfigYaml -Path $configPath

# Determine deployment target
if ($Project) {
    $resolvedProject = (Resolve-Path -LiteralPath $Project).Path
    $targetClaudeMd = Join-Path $resolvedProject "CLAUDE.md"
    $targetAgentsDir = Join-Path (Join-Path $resolvedProject ".claude") "agents"
    $targetSkillsDir = Join-Path (Join-Path $resolvedProject ".claude") "skills"
    $targetCommandsDir = Join-Path (Join-Path $resolvedProject ".claude") "commands"
    $targetRulesDir = Join-Path (Join-Path $resolvedProject ".claude") "rules"
    $markerRoot = $resolvedProject
    $mode = "Project"
    Write-Host "Mode: Project ($resolvedProject)"
} else {
    $homeClaude = Join-Path $env:USERPROFILE ".claude"
    $targetClaudeMd = Join-Path $homeClaude "CLAUDE.md"
    $targetAgentsDir = Join-Path $homeClaude "agents"
    $targetSkillsDir = Join-Path $homeClaude "skills"
    $targetCommandsDir = Join-Path $homeClaude "commands"
    # Rules are project-specific (Claude Code convention) and are not deployed in Global mode.
    $targetRulesDir = $null
    $markerRoot = $homeClaude
    $mode = "Global"
    Write-Host "Mode: Global ($homeClaude)"
}

if ($DryRun) { Write-Host "DryRun: yes" }

$templatesRoot = Join-Path $KitRoot "templates"
$sourceClaudeMd = Join-Path $templatesRoot "CLAUDE.md"
$sourceAgentsDir = Join-Path $templatesRoot "agents"
$sourceSkillsDir = Join-Path $templatesRoot "skills"
$sourceCommandsDir = Join-Path $templatesRoot "commands"

$appliedFiles = @()

# Copy CLAUDE.md
$null = Copy-Template -SourceFile $sourceClaudeMd -DestFile $targetClaudeMd `
    -ModelsConfig $modelsConfig -IsDryRun:$DryRun
$appliedFiles += $targetClaudeMd


# Copy agents/*.md
$agentFiles = Get-ChildItem -LiteralPath $sourceAgentsDir -Filter "*.md" -File
foreach ($agentFile in $agentFiles) {
    $destAgent = Join-Path $targetAgentsDir $agentFile.Name
    $null = Copy-Template -SourceFile $agentFile.FullName -DestFile $destAgent `
        -ModelsConfig $modelsConfig -IsDryRun:$DryRun
    $appliedFiles += $destAgent
}

# Copy skills/<name>/SKILL.md
# Each skill source lives at templates/skills/<name>/SKILL.md. We deploy it to
# <target>/skills/<name>/SKILL.md, preserving the parent directory name as the
# skill name. Substitution is applied via Copy-Template so future role
# placeholders inside a SKILL.md are resolved consistently with other templates.
if (Test-Path $sourceSkillsDir) {
    $skillFiles = Get-ChildItem -LiteralPath $sourceSkillsDir -Recurse -Filter "SKILL.md" -File
    foreach ($skillFile in $skillFiles) {
        $skillName = $skillFile.Directory.Name
        $destSkill = Join-Path (Join-Path $targetSkillsDir $skillName) "SKILL.md"
        $null = Copy-Template -SourceFile $skillFile.FullName -DestFile $destSkill `
            -ModelsConfig $modelsConfig -IsDryRun:$DryRun
        $appliedFiles += $destSkill
    }
}

# Copy commands/*.md
# Each slash command source lives at templates/commands/<name>.md. We deploy it to
# <target>/commands/<name>.md so Claude Code can load it as a /<name> command.
# Substitution is applied via Copy-Template for consistency with other templates.
if (Test-Path $sourceCommandsDir) {
    $commandFiles = Get-ChildItem -LiteralPath $sourceCommandsDir -Filter "*.md" -File
    foreach ($commandFile in $commandFiles) {
        $destCommand = Join-Path $targetCommandsDir $commandFile.Name
        $null = Copy-Template -SourceFile $commandFile.FullName -DestFile $destCommand `
            -ModelsConfig $modelsConfig -IsDryRun:$DryRun
        $appliedFiles += $destCommand
    }
}

# Copy Claude rules (Project mode only)
# Rules are project-specific by Claude Code convention, so they are deployed to
# <project>/.claude/rules/ and are intentionally skipped in Global mode.
# The build pipeline (build-rules.ps1) compiles source/rules/*.md into
# dist/.claude/rules/<id>.md with audience filtering. If dist is missing or
# stale relative to the source, it is rebuilt first. Rules carry no role
# placeholders, so they are copied verbatim (no Copy-Template substitution).
if ($mode -eq "Project") {
    $distRulesDir = Join-Path (Join-Path (Join-Path $KitRoot "dist") ".claude") "rules"
    $sourceRulesDir = Join-Path (Join-Path $KitRoot "source") "rules"
    $buildScript = Join-Path (Join-Path $KitRoot "scripts") "build-rules.ps1"

    # Freshness check: rebuild when dist is absent, empty, or older than source.
    $needBuild = $false
    if (-not (Test-Path $distRulesDir)) {
        $needBuild = $true
    } elseif (Test-Path $sourceRulesDir) {
        $newestSource = Get-ChildItem -LiteralPath $sourceRulesDir -Recurse -Filter "*.md" -File |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $newestDist = Get-ChildItem -LiteralPath $distRulesDir -Filter "*.md" -File |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($null -eq $newestDist) {
            $needBuild = $true
        } elseif ($null -ne $newestSource -and $newestSource.LastWriteTimeUtc -gt $newestDist.LastWriteTimeUtc) {
            $needBuild = $true
        }
    }

    if ($needBuild) {
        if ($DryRun) {
            Write-Host "[dry-run] would build rules from source/rules/ (dist missing or stale)"
        } elseif (Test-Path $buildScript) {
            Write-Host "[rules] dist is missing or stale; building from source/rules/"
            # Switch cwd to the kit root while invoking build-rules.ps1, then restore.
            Push-Location $KitRoot
            try {
                & $buildScript | Out-Null
            } finally {
                Pop-Location
            }
        } else {
            Write-Warning "build-rules.ps1 not found at: $buildScript"
        }
    }

    if (Test-Path $distRulesDir) {
        $ruleFiles = Get-ChildItem -LiteralPath $distRulesDir -Filter "*.md" -File
        foreach ($ruleFile in $ruleFiles) {
            $destRule = Join-Path $targetRulesDir $ruleFile.Name
            if ($DryRun) {
                Write-Host "[dry-run] $($ruleFile.FullName) -> $destRule"
            } else {
                if (-not (Test-Path $targetRulesDir)) {
                    New-Item -ItemType Directory -Force -Path $targetRulesDir | Out-Null
                }
                # Verbatim UTF-8 (no BOM) copy; rules contain no role placeholders.
                $ruleContent = Get-Content -LiteralPath $ruleFile.FullName -Raw
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($destRule, $ruleContent, $utf8NoBom)
                Write-Host "[apply] $($ruleFile.FullName) -> $destRule"
            }
            $appliedFiles += $destRule
        }
    }
}

# Leak-protection artifacts (Project mode only)
# Git hooks and root-level config (.gitleaks.toml / .mailmap / .gitignore) are
# project-specific, so they are intentionally skipped in Global mode.
# Hooks live under <project>/.git/hooks/ and are runtime artifacts: overwriting
# them on re-apply is expected. Root config files, by contrast, are preserved
# when they already exist so user customization is never clobbered.
if ($mode -eq "Project") {
    # Hooks distribution (overwrite OK; runtime artifacts).
    $hooksSourceDir = Join-Path $templatesRoot "git-hooks"
    $projectGitDir = Join-Path $resolvedProject ".git"
    $hooksDestDir = Join-Path $projectGitDir "hooks"
    if ((Test-Path $hooksSourceDir) -and (Test-Path $projectGitDir)) {
        if (-not (Test-Path $hooksDestDir)) {
            New-Item -ItemType Directory -Force -Path $hooksDestDir | Out-Null
        }
        Get-ChildItem -LiteralPath $hooksSourceDir -File | ForEach-Object {
            $dest = Join-Path $hooksDestDir $_.Name
            if ($DryRun) {
                Write-Host "[dry-run] $($_.FullName) -> $dest"
            } else {
                # Verbatim copy. Hook bodies are LF + shebang; Git for Windows
                # executes them via its bundled sh. POSIX execute bit (chmod +x)
                # is not settable from PowerShell and is unnecessary on Windows.
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                Write-Host "[apply] $($_.FullName) -> $dest"
            }
            $appliedFiles += $dest
        }
    }

    # Root config distribution (skip when the file already exists).
    $rootFiles = @(".gitleaks.toml", ".mailmap", ".gitignore")
    foreach ($rootFile in $rootFiles) {
        $source = Join-Path $templatesRoot $rootFile
        $dest = Join-Path $resolvedProject $rootFile
        if ((Test-Path $source) -and -not (Test-Path $dest)) {
            if ($DryRun) {
                Write-Host "[dry-run] $source -> $dest"
            } else {
                Copy-Item -LiteralPath $source -Destination $dest
                Write-Host "[apply] $source -> $dest"
            }
            $appliedFiles += $dest
        } elseif (Test-Path $dest) {
            Write-Host "[skip] $dest already exists (preserving user customization)"
        }
    }
}

# Work schedule config (Global mode only)
# config/work-schedule.yaml powers the work-end-reminder rule (ADR-0006). A
# single global copy at ~/.claude/work-schedule.yaml covers every project, so
# it is intentionally skipped in Project mode. It is preserved when it already
# exists so the user's edited schedule is never clobbered (same policy as the
# Group C root config files above).
if ($mode -eq "Global") {
    $scheduleSource = Join-Path (Join-Path $KitRoot "config") "work-schedule.yaml"
    $scheduleDest = Join-Path $homeClaude "work-schedule.yaml"
    if ((Test-Path $scheduleSource) -and -not (Test-Path $scheduleDest)) {
        if ($DryRun) {
            Write-Host "[dry-run] $scheduleSource -> $scheduleDest"
        } else {
            # Plain YAML, no role placeholders: verbatim UTF-8 (no BOM) copy.
            $scheduleContent = Get-Content -LiteralPath $scheduleSource -Raw
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($scheduleDest, $scheduleContent, $utf8NoBom)
            Write-Host "[apply] $scheduleSource -> $scheduleDest"
            Write-Host "[hint] To enable work-end reminder, edit ~/.claude/work-schedule.yaml with your work schedule."
        }
        $appliedFiles += $scheduleDest
    } elseif (Test-Path $scheduleDest) {
        Write-Host "[skip] $scheduleDest already exists (preserving user customization)"
    }
}

# Write marker file
if (-not $DryRun) {
    Write-AppliedMarker -TargetRoot $markerRoot -Mode $mode -AppliedFiles $appliedFiles
}

Write-Host ""
# Hands-off settings.json (ADR-0007): the kit no longer manages settings.json.
# Display a hint pointing users to docs/setup/.
Write-Host ""
Write-Host "[hint] settings.json is NOT managed by this kit (hands-off policy, see ADR-0007)."
Write-Host "       Setup guide and examples: <kit>/docs/setup/settings-setup.md"
Write-Host "       - For Bedrock environment: docs/setup/settings-bedrock.example.json"
Write-Host "       - For Anthropic API direct: docs/setup/settings-anthropic.example.json"

Write-Host "Applied $($appliedFiles.Count) file(s) in $mode mode."
if ($DryRun) { Write-Host "Note: -DryRun was specified, no files were modified." }
