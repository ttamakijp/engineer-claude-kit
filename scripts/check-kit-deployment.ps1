#!/usr/bin/env pwsh
# check-kit-deployment.ps1
# Verifies what the kit actually put under ~/.claude, not what it meant to put
# there. ASCII only (no Japanese in code, comments, or strings). See ADR-0017.
#
# Written after two bugs of the same shape: a rule held back at the source
# filter kept being deployed because dist was never pruned (PR #103), and the
# local-llm delegation config was never deployed at all while CLAUDE.md
# instructed every session to read it. Both were invisible from inside the repo
# -- the source said the right thing and nothing checked the target. This script
# is the check. Exit code 0 = every assertion held, 1 = at least one failed.

[CmdletBinding()]
param(
    [string]$TargetRoot,
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'

$here = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}
if (-not $KitRoot) { $KitRoot = (Resolve-Path -LiteralPath (Join-Path $here "..")).Path }
if (-not $TargetRoot) {
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    $TargetRoot = Join-Path $userHome ".claude"
}

. (Join-Path (Join-Path $here "lib") "encoding-helper.ps1")

$script:Failures = @()
$script:Checked = 0
function Assert-KitState {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][bool]$Condition,
        [string]$Detail
    )
    $script:Checked++
    if ($Condition) {
        Write-Host "  [ok]   $What"
    } else {
        Write-Host "  [FAIL] $What"
        if ($Detail) { Write-Host "         $Detail" }
        $script:Failures += $What
    }
}

Write-Host "check-kit-deployment.ps1"
Write-Host "  kit:    $KitRoot"
Write-Host "  target: $TargetRoot"
Write-Host ""

# --- 1. rules: every rule the build emits has to be deployed, and nothing else
Write-Host "rules"
$distRules = Join-Path (Join-Path (Join-Path $KitRoot "dist") ".claude") "rules"
$targetRules = Join-Path $TargetRoot "rules"
$expected = @()
if (Test-Path $distRules) {
    $expected = @(Get-ChildItem -LiteralPath $distRules -Filter "*.md" -File | ForEach-Object { $_.Name })
}
Assert-KitState -What "dist holds at least one built rule" -Condition ($expected.Count -gt 0) `
    -Detail "run scripts/build-rules.ps1 first: $distRules"
foreach ($name in $expected) {
    Assert-KitState -What "deployed: rules/$name" -Condition (Test-Path (Join-Path $targetRules $name))
}
# A rule the build no longer emits must not survive in the target. This is the
# PR #103 failure mode seen from the other end.
if (Test-Path $targetRules) {
    $sourceDir = Join-Path (Join-Path $KitRoot "source") "rules"
    $heldBack = @()
    if (Test-Path $sourceDir) {
        foreach ($src in (Get-ChildItem -LiteralPath $sourceDir -Recurse -Filter "*.md" -File)) {
            $text = Read-Utf8NoBom -Path $src.FullName
            if ($text -match "(?m)^audience:" -and $text -notmatch "(?m)^audience:.*\bclaude\b") {
                if ($text -match "(?m)^id:\s*(\S+)") { $heldBack += ($Matches[1] + ".md") }
            }
        }
    }
    foreach ($name in $heldBack) {
        Assert-KitState -What "held back, so absent: rules/$name" `
            -Condition (-not (Test-Path (Join-Path $targetRules $name))) `
            -Detail "audience excludes 'claude' but the file is deployed; re-run apply"
    }
}

# --- 2. local-llm delegation config and the prompts it names (ADR-0017)
Write-Host "local-llm delegation"
$cfgDest = Join-Path (Join-Path $TargetRoot "config") "local-llm-delegation.yaml"
Assert-KitState -What "deployed: config/local-llm-delegation.yaml" -Condition (Test-Path $cfgDest) `
    -Detail "run apply-claude-kit.ps1 -Global"
if (Test-Path $cfgDest) {
    $cfgText = Read-Utf8NoBom -Path $cfgDest
    $refs = @([regex]::Matches($cfgText, "(?m)^\s*system_prompt_ref:\s*(\S+)") | ForEach-Object { $_.Groups[1].Value })
    Assert-KitState -What "config names at least one system prompt" -Condition ($refs.Count -gt 0)
    $cfgDir = Split-Path -Parent $cfgDest
    foreach ($ref in $refs) {
        # system_prompt_ref is relative to the directory holding the yaml, so it
        # has to resolve against the deployed copy, not against the kit.
        Assert-KitState -What "prompt resolves: $ref" -Condition (Test-Path (Join-Path $cfgDir $ref)) `
            -Detail "expected at $(Join-Path $cfgDir $ref)"
    }
}

# --- 3. the instruction and the deployed config have to agree on the path
Write-Host "instructions"
$claudeMd = Join-Path $TargetRoot "CLAUDE.md"
Assert-KitState -What "deployed: CLAUDE.md" -Condition (Test-Path $claudeMd)
if (Test-Path $claudeMd) {
    $mdText = Read-Utf8NoBom -Path $claudeMd
    Assert-KitState -What "CLAUDE.md points at the deployed config" `
        -Condition ($mdText -match [regex]::Escape('~/.claude/config/local-llm-delegation.yaml')) `
        -Detail "section 3 still names another path; re-run apply"
    # Pointing at the kit checkout makes a session's behaviour depend on the
    # branch that happens to be checked out there.
    Assert-KitState -What "CLAUDE.md does not point into the kit checkout" `
        -Condition (-not ($mdText -match [regex]::Escape('~/.claude-kit/config/local-llm-delegation.yaml')))
}
$triggerRule = Join-Path $targetRules "local-llm-delegation.md"
Assert-KitState -What "deployed: rules/local-llm-delegation.md (firing conditions)" `
    -Condition (Test-Path $triggerRule) `
    -Detail "without it a session has the criterion but no trigger; snapshot 4 measured 0 calls"

# --- 4. agents: the shipped set has to be deployed, the withdrawn set absent
# Claude Code offers every file in <target>/agents/ as a delegation target and
# shows its description in the session's agent roster, so this directory decides
# what a session believes it may delegate to. The three Haiku delegation agents
# were withdrawn (ADR-0016 decision B) while CLAUDE.md section 3 already forbade
# Haiku delegation; a surviving copy contradicts the instruction every session.
# Failing rather than warning is the point: apply now removes them, so a hit
# here means the deploy did not take, which is exactly what a re-apply fixes.
Write-Host "agents"
$agentsDir = Join-Path $TargetRoot "agents"
$templateAgents = @()
$templateAgentDir = Join-Path (Join-Path $KitRoot "templates") "agents"
if (Test-Path $templateAgentDir) {
    $templateAgents = @(Get-ChildItem -LiteralPath $templateAgentDir -Filter "*.md" -File |
        ForEach-Object { $_.Name })
}
foreach ($name in $templateAgents) {
    Assert-KitState -What "deployed: agents/$name" -Condition (Test-Path (Join-Path $agentsDir $name)) `
        -Detail "run apply-claude-kit.ps1 -Global"
}
# Named explicitly, not derived: these three are gone from templates/, so a
# check derived only from what the kit ships could never notice them again.
foreach ($withdrawn in @("commit-msg.md", "log-summary.md", "lint-helper.md")) {
    Assert-KitState -What "withdrawn, so absent: agents/$withdrawn" `
        -Condition (-not (Test-Path (Join-Path $agentsDir $withdrawn))) `
        -Detail "CLAUDE.md section 3 forbids Haiku delegation, but this agent advertises it every session; re-run apply"
}

Write-Host ""
if ($script:Failures.Count -eq 0) {
    Write-Host "PASS - $($script:Checked) check(s), no issues"
    exit 0
}
Write-Host "FAIL - $($script:Failures.Count) of $($script:Checked) check(s) failed:"
foreach ($f in $script:Failures) { Write-Host "  - $f" }
exit 1
