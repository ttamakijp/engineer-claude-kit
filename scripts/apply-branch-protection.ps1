#requires -Version 5.1
# apply-branch-protection.ps1
# Create or reconcile the kit's protect-main ruleset on a GitHub repository.
#
# Behaviour:
#   not applied -> POST repos/OWNER/REPO/rulesets  (creates the ruleset)
#   drift       -> show the diff, ask Y/N, then PUT repos/.../rulesets/<id>
#   match       -> nothing to do
#
# -DryRun reports what would happen and writes nothing. -Force answers the drift
# prompt with yes (non-interactive automation). Without either, a drift found in
# a non-interactive context aborts instead of hanging on Read-Host.
#
# Usage:
#   powershell -NoProfile -File scripts/apply-branch-protection.ps1 -Repo OWNER/REPO
#   pwsh scripts/apply-branch-protection.ps1 -Repo OWNER/REPO -DryRun
#
# Exit codes: 0 = applied / already correct, 1 = declined or drift left as-is,
#             3 = error.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible.

[CmdletBinding()]
param(
    # OWNER/REPO. Inferred from the git remote of -Path when omitted.
    [string]$Repo,

    # Ruleset name to create / reconcile.
    [string]$Name = "protect-main",

    # Canonical ruleset JSON. Defaults to the kit's template.
    [string]$TemplatePath,

    # Repository checkout used to infer -Repo.
    [string]$Path = ".",

    # Report only; never writes to GitHub.
    [switch]$DryRun,

    # Skip the drift confirmation prompt (answer yes).
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot "lib") "branch-protection.ps1")
# Test-IsInteractive (CI / UserInteractive / stdin-redirected) is already solved
# in the settings wizard; reuse it rather than duplicating the three signals.
. (Join-Path $PSScriptRoot "setup-wizard.ps1")

function Invoke-RulesetWrite {
    # POST (create) or PUT (update) the ruleset. Returns $true on success.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Body,
        [string]$RulesetId,
        [scriptblock]$Invoker
    )

    $endpoint = "repos/$Repo/rulesets"
    if ($RulesetId) { $endpoint = "$endpoint/$RulesetId" }
    # Not $args: that is a PowerShell automatic variable.
    $apiArgs = @('api', '-X', $Method, $endpoint, '--input', '-')

    if ($PSBoundParameters.ContainsKey('Invoker')) {
        $res = Invoke-GhApi -Arguments $apiArgs -Body $Body -Invoker $Invoker
    } else {
        $res = Invoke-GhApi -Arguments $apiArgs -Body $Body
    }
    if ($res.ExitCode -ne 0) {
        Write-Host "[error] gh api -X $Method $endpoint failed (exit $($res.ExitCode)):"
        Write-Host $res.Output
        return $false
    }
    return $true
}

function Invoke-BranchProtectionApply {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string]$Name = "protect-main",
        [string]$TemplatePath,
        [string]$Path = ".",
        [switch]$DryRun,
        [switch]$Force,
        [scriptblock]$Invoker,
        # Test injection point: answers the drift prompt without a console.
        [string]$PromptAnswer
    )

    if (-not $Repo) {
        $Repo = Get-RepoFromGitRemote -Path $Path
        if (-not $Repo) {
            Write-Host "[error] -Repo was not given and no GitHub remote could be resolved from: $Path"
            return 3
        }
        Write-Host "[info] repo inferred from git remote: $Repo"
    }

    $expected = Read-RulesetTemplate -Path $TemplatePath
    $ghArgs = @{}
    if ($PSBoundParameters.ContainsKey('Invoker')) { $ghArgs['Invoker'] = $Invoker }

    $actual = Get-RepoRuleset -Repo $Repo -Name $Name @ghArgs
    $result = Compare-RulesetState -Expected $expected -Actual $actual
    foreach ($line in (Format-RulesetReport -Repo $Repo -Name $Name -Result $result)) {
        Write-Host $line
    }

    if ($result.Status -eq 'match') { return 0 }

    $body = New-RulesetRequestBody -Template $expected

    if ($result.Status -eq 'missing') {
        if ($DryRun) {
            Write-Host "[dry-run] would POST repos/$Repo/rulesets (create '$Name')."
            return 0
        }
        Write-Host "[apply] creating ruleset '$Name' on $Repo ..."
        if (Invoke-RulesetWrite -Repo $Repo -Method 'POST' -Body $body @ghArgs) {
            Write-Host "[OK] ruleset '$Name' created."
            return 0
        }
        return 3
    }

    # drift
    if ($DryRun) {
        Write-Host "[dry-run] would PUT repos/$Repo/rulesets/$($actual.id) (reconcile '$Name')."
        return 0
    }

    $answer = $null
    if ($Force) {
        $answer = 'y'
    } elseif ($PSBoundParameters.ContainsKey('PromptAnswer')) {
        $answer = $PromptAnswer
    } elseif (Test-IsInteractive) {
        Write-Host ""
        $answer = Read-Host "Update the ruleset to match the kit template? [y/N]"
    } else {
        Write-Host "[skip] non-interactive context. Re-run with -Force to reconcile without a prompt."
        return 1
    }

    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "[skip] ruleset left unchanged."
        return 1
    }

    Write-Host "[apply] updating ruleset '$Name' on $Repo ..."
    if (Invoke-RulesetWrite -Repo $Repo -Method 'PUT' -Body $body -RulesetId ([string]$actual.id) @ghArgs) {
        Write-Host "[OK] ruleset '$Name' updated."
        return 0
    }
    return 3
}

# Direct-invocation entry point. Dot-sourcing loads the functions only.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $TemplatePath) {
        $kitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
        $TemplatePath = Join-Path (Join-Path $kitRoot "templates") "branch-protection"
        $TemplatePath = Join-Path $TemplatePath "protect-main.json"
    }
    try {
        $code = Invoke-BranchProtectionApply -Repo $Repo -Name $Name `
            -TemplatePath $TemplatePath -Path $Path -DryRun:$DryRun -Force:$Force
    } catch {
        Write-Host "[error] $_"
        $code = 3
    }
    exit $code
}
