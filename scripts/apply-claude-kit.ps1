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

    # Skip the interactive settings wizard entirely (ADR-0010). bootstrap.ps1
    # passes this so the wizard runs once at the end of bootstrap, not twice.
    [switch]$NoSettingsWizard,

    # Force the settings wizard into non-interactive (skip) mode regardless of
    # console state. Honored only when the wizard would otherwise run (Global).
    [switch]$NonInteractive,

    # Opt-in: deploy the cleanup-orphan-processes scheduled-task spec (ADR-0011).
    # Off by default; the skill + slash command always ship, but the hourly task
    # spec is only placed when this is passed (Global mode only).
    [switch]$EnableCleanupSchedule,

    # Kit self-update (ADR-0013). On startup the kit checks whether its own
    # checkout is behind origin and prints an opt-in hint. -Update performs a
    # fast-forward pull; -UpdateForce hard-resets to origin (escape hatch);
    # -NoUpdateCheck skips the check entirely (CI / offline).
    [switch]$Update,
    [switch]$UpdateForce,
    [switch]$NoUpdateCheck,

    # Default resolved in the body: referencing $PSScriptRoot in a param default
    # is unreliable under Windows PowerShell 5.1 when parameter sets are present.
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "0.1.0"

# Fail-fast if running as Administrator (see ADR-0008). Escape hatch: -AllowElevated.
. (Join-Path (Join-Path $PSScriptRoot "lib") "privilege-check.ps1")
Assert-NonElevated -AllowElevated:$AllowElevated

# UTF-8 (no BOM) file I/O helpers. All reads/writes of templates, rules, config,
# and generated files go through these so source content is never decoded with
# the host's default codepage (CP932 on PS 5.1 -> mojibake). See ADR-0003 section C.
. (Join-Path (Join-Path $PSScriptRoot "lib") "encoding-helper.ps1")

# Config loader + model-role resolution: Read-ConfigYaml, Resolve-ModelId,
# Invoke-TemplateSubstitution. Extracted to lib/ to keep this script under the
# file-granularity hard limit (500 lines). Depends on Read-Utf8NoBom above.
. (Join-Path (Join-Path $PSScriptRoot "lib") "models-config.ps1")

if (-not $KitRoot) {
    $KitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

# Kit self-update check (ADR-0013). Detect whether this kit checkout is behind
# origin and, depending on the switches, hint / pull / hard-reset. A network
# failure, timeout, or non-git checkout returns -1 and is silently ignored so a
# flaky network never blocks apply. -NoUpdateCheck skips the check entirely.
if (-not $NoUpdateCheck) {
    . (Join-Path (Join-Path $PSScriptRoot "lib") "kit-updater.ps1")
    $behind = Test-KitBehind -KitRoot $KitRoot
    if ($behind -gt 0) {
        Write-Host ""
        Write-Host "[hint] kit is $behind commit(s) behind origin."
        if ($Update) {
            Invoke-KitUpdate -KitRoot $KitRoot
        } elseif ($UpdateForce) {
            Invoke-KitUpdate -KitRoot $KitRoot -Force
        } else {
            Write-Host "       Run with -Update to pull (fast-forward only)."
            Write-Host "       Or update manually: git -C `"$KitRoot`" pull"
        }
        Write-Host ""
    } elseif ($Update -or $UpdateForce) {
        Write-Host "[OK] kit is already up-to-date."
    }
    # behind == -1 (network failure / timeout / non-git checkout): stay silent.
}

# --- deployment ---

function Copy-Template {
    param(
        [string]$SourceFile,
        [string]$DestFile,
        [hashtable]$ModelsConfig,
        [switch]$IsDryRun
    )

    $content = Read-Utf8NoBom -Path $SourceFile
    $rendered = Invoke-TemplateSubstitution -TemplateContent $content -ModelsConfig $ModelsConfig

    if ($IsDryRun) {
        Write-Host "[dry-run] $SourceFile -> $DestFile"
        return $DestFile
    }

    $destDir = Split-Path -Parent $DestFile
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    # UTF-8 without BOM on every PowerShell version (see encoding-helper.ps1).
    Write-Utf8NoBom -Path $DestFile -Content $rendered
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
    Write-Utf8NoBom -Path $markerPath -Content $marker
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
                $ruleContent = Read-Utf8NoBom -Path $ruleFile.FullName
                Write-Utf8NoBom -Path $destRule -Content $ruleContent
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
            $scheduleContent = Read-Utf8NoBom -Path $scheduleSource
            Write-Utf8NoBom -Path $scheduleDest -Content $scheduleContent
            Write-Host "[apply] $scheduleSource -> $scheduleDest"
            Write-Host "[hint] To enable work-end reminder, edit ~/.claude/work-schedule.yaml with your work schedule."
        }
        $appliedFiles += $scheduleDest
    } elseif (Test-Path $scheduleDest) {
        Write-Host "[skip] $scheduleDest already exists (preserving user customization)"
    }
}

# Cleanup-orphan-processes scheduled task (Global mode, opt-in only -- ADR-0011)
# The cleanup skill and /cleanup-processes command always ship (generic skill /
# command loops above). The hourly scheduled-task spec is heavier-handed (auto
# kill on a timer), so it is placed only when -EnableCleanupSchedule is passed.
# Specs live at templates/scheduled-tasks/<name>/<file>.md and deploy to
# ~/.claude/scheduled-tasks/<name>/<file>.md, preserving the parent dir as the
# task name (mirrors the skills layout). They carry no role placeholders, so
# they are copied verbatim.
if ($mode -eq "Global" -and $EnableCleanupSchedule) {
    $sourceSchedTasksDir = Join-Path $templatesRoot "scheduled-tasks"
    $targetSchedTasksDir = Join-Path $homeClaude "scheduled-tasks"
    if (Test-Path $sourceSchedTasksDir) {
        $schedTaskFiles = Get-ChildItem -LiteralPath $sourceSchedTasksDir -Recurse -Filter "*.md" -File
        foreach ($schedTaskFile in $schedTaskFiles) {
            $taskName = $schedTaskFile.Directory.Name
            $destSchedTask = Join-Path (Join-Path $targetSchedTasksDir $taskName) $schedTaskFile.Name
            if ($DryRun) {
                Write-Host "[dry-run] $($schedTaskFile.FullName) -> $destSchedTask"
            } else {
                $schedTaskContent = Read-Utf8NoBom -Path $schedTaskFile.FullName
                Write-Utf8NoBom -Path $destSchedTask -Content $schedTaskContent
                Write-Host "[apply] $($schedTaskFile.FullName) -> $destSchedTask"
            }
            $appliedFiles += $destSchedTask
        }
        if (-not $DryRun) {
            Write-Host "[hint] Cleanup scheduled-task spec deployed. To run it hourly, register it"
            Write-Host "       with Windows Task Scheduler (see docs/setup/cleanup-processes.md)."
        }
    }
} elseif ($mode -eq "Global") {
    Write-Host "[skip] cleanup scheduled-task not deployed (pass -EnableCleanupSchedule to opt in)."
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

# Optional interactive settings wizard (ADR-0010), Global mode only.
# This is the sanctioned exception to the ADR-0007 hands-off policy: it asks
# before every change and only deep-merges missing keys. Skipped on -DryRun (no
# modifications), -NoSettingsWizard, and in Project mode. The wizard itself
# skips in non-interactive contexts, so non-interactive callers are unaffected.
if ($mode -eq "Global" -and -not $DryRun -and -not $NoSettingsWizard) {
    . (Join-Path $PSScriptRoot "setup-wizard.ps1")
    Invoke-SettingsSetupWizard -NonInteractive:$NonInteractive
}
