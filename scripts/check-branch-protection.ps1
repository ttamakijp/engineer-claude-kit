#requires -Version 5.1
# check-branch-protection.ps1
# Report whether a repository has the kit's protect-main ruleset applied.
# Read-only: this script never writes to GitHub. Use apply-branch-protection.ps1
# to create or reconcile the ruleset.
#
# Usage:
#   powershell -NoProfile -File scripts/check-branch-protection.ps1 -Repo OWNER/REPO
#   pwsh scripts/check-branch-protection.ps1        # -Repo inferred from git remote
#
# Exit codes: 0 = applied (match), 1 = drift, 2 = not applied, 3 = error.
# The last output line is always "STATUS: match|drift|missing" for callers that
# prefer parsing over exit codes.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible.

[CmdletBinding()]
param(
    # OWNER/REPO. Inferred from the git remote of -Path when omitted.
    [string]$Repo,

    # Ruleset name to look for.
    [string]$Name = "protect-main",

    # Canonical ruleset JSON. Defaults to the kit's template.
    [string]$TemplatePath,

    # Repository checkout used to infer -Repo.
    [string]$Path = "."
)

$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot "lib") "branch-protection.ps1")

function Invoke-BranchProtectionCheck {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string]$Name = "protect-main",
        [string]$TemplatePath,
        [string]$Path = ".",
        [scriptblock]$Invoker
    )

    if (-not $Repo) {
        $Repo = Get-RepoFromGitRemote -Path $Path
        if (-not $Repo) {
            Write-Host "[error] -Repo was not given and no GitHub remote could be resolved from: $Path"
            Write-Host "        Pass -Repo OWNER/REPO explicitly."
            return 3
        }
        Write-Host "[info] repo inferred from git remote: $Repo"
    }

    $expected = Read-RulesetTemplate -Path $TemplatePath
    if ($PSBoundParameters.ContainsKey('Invoker')) {
        $actual = Get-RepoRuleset -Repo $Repo -Name $Name -Invoker $Invoker
    } else {
        $actual = Get-RepoRuleset -Repo $Repo -Name $Name
    }

    $result = Compare-RulesetState -Expected $expected -Actual $actual
    foreach ($line in (Format-RulesetReport -Repo $Repo -Name $Name -Result $result)) {
        Write-Host $line
    }
    return (Get-BranchProtectionExitCode -Status $result.Status)
}

# Direct-invocation entry point. Dot-sourcing loads the function only.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $TemplatePath) {
        $kitRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
        $TemplatePath = Join-Path (Join-Path $kitRoot "templates") "branch-protection"
        $TemplatePath = Join-Path $TemplatePath "protect-main.json"
    }
    try {
        $code = Invoke-BranchProtectionCheck -Repo $Repo -Name $Name `
            -TemplatePath $TemplatePath -Path $Path
    } catch {
        Write-Host "[error] $_"
        $code = 3
    }
    exit $code
}
