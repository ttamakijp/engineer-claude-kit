# branch-protection.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# No network and no gh process is ever launched: Get-RepoRuleset is driven
# through its -Invoker injection point, and Get-RepoFromGitRemote is driven
# through -Url. Comparison cases build their "actual" ruleset by re-parsing the
# shipped template and mutating the copy, so the template itself stays the
# single source of truth for the expected shape.
#
# The helper is dot-sourced ONCE at file scope; re-sourcing inside an It
# re-defines the functions and silently defeats Pester 3.4 Mocks.
#
# PS 5.1: Join-Path takes exactly two arguments, hence the nesting below.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$KitRoot = (Resolve-Path -LiteralPath (Join-Path $here "..")).Path
$ScriptsDir = Join-Path $KitRoot "scripts"
$LibPath = Join-Path (Join-Path $ScriptsDir "lib") "branch-protection.ps1"
$TemplatesRoot = Join-Path $KitRoot "templates"
$TemplatePath = Join-Path (Join-Path $TemplatesRoot "branch-protection") "protect-main.json"

. $LibPath

function New-ActualRuleset {
    # Fresh deep copy of the shipped template, standing in for an API response.
    param([int]$Id = 42)
    $obj = (Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json)
    $obj | Add-Member -NotePropertyName id -NotePropertyValue $Id -Force
    return $obj
}

function Get-PullRequestParameters {
    param($Ruleset)
    return ($Ruleset.rules | Where-Object { $_.type -eq 'pull_request' }).parameters
}

Describe "branch-protection deliverables" {

    It "ships the ruleset template" {
        Test-Path $TemplatePath | Should Be $true
    }

    It "ships both PowerShell entry points and the shared helper" {
        Test-Path $LibPath | Should Be $true
        Test-Path (Join-Path $ScriptsDir "check-branch-protection.ps1") | Should Be $true
        Test-Path (Join-Path $ScriptsDir "apply-branch-protection.ps1") | Should Be $true
    }

    It "ships both bash entry points and the shared helper" {
        Test-Path (Join-Path (Join-Path $ScriptsDir "lib") "branch-protection.sh") | Should Be $true
        Test-Path (Join-Path $ScriptsDir "check-branch-protection.sh") | Should Be $true
        Test-Path (Join-Path $ScriptsDir "apply-branch-protection.sh") | Should Be $true
    }

    It "ships the skill and the scheduled-task spec" {
        $skill = Join-Path (Join-Path (Join-Path $TemplatesRoot "skills") "branch-protection-check") "SKILL.md"
        $task = Join-Path (Join-Path (Join-Path $TemplatesRoot "scheduled-tasks") "check-branch-protection") "check-branch-protection.md"
        Test-Path $skill | Should Be $true
        Test-Path $task | Should Be $true
    }

    It "parses every PowerShell file without syntax errors" {
        $files = @(
            $LibPath,
            (Join-Path $ScriptsDir "check-branch-protection.ps1"),
            (Join-Path $ScriptsDir "apply-branch-protection.ps1")
        )
        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should Be 0
        }
    }

    It "declares the four required frontmatter keys on the scheduled task" {
        $task = Join-Path (Join-Path (Join-Path $TemplatesRoot "scheduled-tasks") "check-branch-protection") "check-branch-protection.md"
        $body = Get-Content -LiteralPath $task -Raw
        ($body -match '(?m)^name:\s*check-branch-protection') | Should Be $true
        ($body -match '(?m)^description:\s*\S') | Should Be $true
        ($body -match '(?m)^\s+cronExpression:\s*"') | Should Be $true
        ($body -match '(?m)^version:\s*\d+\.\d+\.\d+') | Should Be $true
    }
}

Describe "Read-RulesetTemplate" {

    It "parses the shipped template into the expected shape" {
        $tpl = Read-RulesetTemplate -Path $TemplatePath
        $tpl.name | Should Be "protect-main"
        $tpl.target | Should Be "branch"
        $tpl.enforcement | Should Be "active"
        @($tpl.rules).Count | Should Be 4
        @($tpl.conditions.ref_name.include)[0] | Should Be "~DEFAULT_BRANCH"
    }

    It "throws when the template is missing" {
        $threw = $false
        try { Read-RulesetTemplate -Path (Join-Path $here "no-such-ruleset.json") } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe "New-RulesetRequestBody" {

    It "drops response-only fields and keeps the rule payload" {
        $body = New-RulesetRequestBody -Template (Read-RulesetTemplate -Path $TemplatePath)
        ($body -match 'source_type') | Should Be $false
        ($body -match '"name":"protect-main"') | Should Be $true
        ($body -match 'required_linear_history') | Should Be $true
    }
}

Describe "Get-RepoFromGitRemote" {

    It "parses the HTTPS form" {
        Get-RepoFromGitRemote -Url "https://github.com/ttamakijp/windows-shortcut-hud.git" | Should Be "ttamakijp/windows-shortcut-hud"
    }

    It "parses the scp-like SSH form" {
        Get-RepoFromGitRemote -Url "git@github.com:ttamakijp/engineer-claude-kit.git" | Should Be "ttamakijp/engineer-claude-kit"
    }

    It "parses the ssh:// form" {
        Get-RepoFromGitRemote -Url "ssh://git@github.com/owner/repo" | Should Be "owner/repo"
    }

    It "returns null for a non-GitHub remote" {
        Get-RepoFromGitRemote -Url "https://gitlab.com/owner/repo.git" | Should BeNullOrEmpty
    }
}

Describe "Compare-RulesetState" {

    It "reports missing when the repository has no such ruleset" {
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $null
        $result.Status | Should Be "missing"
    }

    It "reports match for an identical ruleset" {
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual (New-ActualRuleset)
        $result.Status | Should Be "match"
        @($result.Differences).Count | Should Be 0
    }

    It "tolerates parameters GitHub adds on its own (subset comparison)" {
        $actual = New-ActualRuleset
        (Get-PullRequestParameters -Ruleset $actual) |
            Add-Member -NotePropertyName automatic_copilot_code_review_enabled -NotePropertyValue $false -Force
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "match"
    }

    It "ignores member order inside an array parameter" {
        $actual = New-ActualRuleset
        (Get-PullRequestParameters -Ruleset $actual).allowed_merge_methods = @('squash', 'rebase', 'merge')
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "match"
    }

    It "reports drift when enforcement is not active" {
        $actual = New-ActualRuleset
        $actual.enforcement = 'disabled'
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "drift"
        ($result.Differences -join '|') -match 'enforcement' | Should Be $true
    }

    It "reports drift for a missing rule type and for an unexpected one" {
        $actual = New-ActualRuleset
        $actual.rules = @($actual.rules | Where-Object { $_.type -ne 'deletion' })
        $actual.rules += ([PSCustomObject]@{ type = 'creation' })
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "drift"
        ($result.Differences -join '|') -match "missing rule type 'deletion'" | Should Be $true
        ($result.Differences -join '|') -match "unexpected rule type 'creation'" | Should Be $true
    }

    It "reports drift when a bypass actor is present" {
        $actual = New-ActualRuleset
        $actual.bypass_actors = @([PSCustomObject]@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' })
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "drift"
        ($result.Differences -join '|') -match 'bypass_actors' | Should Be $true
    }

    It "reports drift when a declared parameter value differs" {
        $actual = New-ActualRuleset
        (Get-PullRequestParameters -Ruleset $actual).required_approving_review_count = 2
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "drift"
        ($result.Differences -join '|') -match 'required_approving_review_count' | Should Be $true
    }

    It "reports drift when the condition targets a different ref" {
        $actual = New-ActualRuleset
        $actual.conditions.ref_name.include = @('refs/heads/release')
        $result = Compare-RulesetState -Expected (Read-RulesetTemplate -Path $TemplatePath) -Actual $actual
        $result.Status | Should Be "drift"
        ($result.Differences -join '|') -match 'ref_name.include' | Should Be $true
    }
}

Describe "Format-RulesetReport" {

    It "ends every report with a machine-readable STATUS line" {
        foreach ($status in @('match', 'drift', 'missing')) {
            $result = [PSCustomObject]@{ Status = $status; Differences = @('x: expected=1 actual=2') }
            $lines = @(Format-RulesetReport -Repo 'o/r' -Name 'protect-main' -Result $result)
            $lines[-1] | Should Be "STATUS: $status"
        }
    }
}

Describe "Get-BranchProtectionExitCode" {

    It "maps each status to its documented exit code" {
        Get-BranchProtectionExitCode -Status 'match'   | Should Be 0
        Get-BranchProtectionExitCode -Status 'drift'   | Should Be 1
        Get-BranchProtectionExitCode -Status 'missing' | Should Be 2
        Get-BranchProtectionExitCode -Status 'weird'   | Should Be 3
    }
}

Describe "Get-RepoRuleset (injected gh invoker)" {

    It "re-fetches the detail endpoint for the matching ruleset" {
        $detail = Get-Content -LiteralPath $TemplatePath -Raw
        $invoker = {
            param($Arguments, $Body)
            if ($Arguments[1] -eq 'repos/o/r/rulesets') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '[{"id":42,"name":"protect-main"},{"id":7,"name":"other"}]' }
            }
            if ($Arguments[1] -eq 'repos/o/r/rulesets/42') {
                return [PSCustomObject]@{ ExitCode = 0; Output = $detail }
            }
            return [PSCustomObject]@{ ExitCode = 1; Output = "unexpected endpoint: $($Arguments[1])" }
        }.GetNewClosure()
        $ruleset = Get-RepoRuleset -Repo 'o/r' -Invoker $invoker
        $ruleset.name | Should Be 'protect-main'
    }

    It "returns null when no ruleset carries the name" {
        $invoker = { param($Arguments, $Body) [PSCustomObject]@{ ExitCode = 0; Output = '[{"id":7,"name":"other"}]' } }
        $ruleset = Get-RepoRuleset -Repo 'o/r' -Invoker $invoker
        $ruleset | Should BeNullOrEmpty
    }

    It "returns null for a repository with no rulesets at all" {
        $invoker = { param($Arguments, $Body) [PSCustomObject]@{ ExitCode = 0; Output = '[]' } }
        $ruleset = Get-RepoRuleset -Repo 'o/r' -Invoker $invoker
        $ruleset | Should BeNullOrEmpty
    }

    It "throws when gh reports a failure" {
        $invoker = { param($Arguments, $Body) [PSCustomObject]@{ ExitCode = 1; Output = 'gh: Not Found (HTTP 404)' } }
        $threw = $false
        try { Get-RepoRuleset -Repo 'o/r' -Invoker $invoker } catch { $threw = $true }
        $threw | Should Be $true
    }
}

Describe "Copy-BranchProtectionTask" {

    It "is a silent no-op in Project mode" {
        $deployed = @(Copy-BranchProtectionTask -Mode 'Project' -TemplatesRoot $TemplatesRoot -TargetRoot $here -Enabled)
        $deployed.Count | Should Be 0
    }

    It "deploys nothing when the opt-in switch is absent" {
        $deployed = @(Copy-BranchProtectionTask -Mode 'Global' -TemplatesRoot $TemplatesRoot -TargetRoot $here)
        $deployed.Count | Should Be 0
    }

    It "writes no file under -IsDryRun but reports the destination" {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-dry-" + [guid]::NewGuid().ToString('N'))
        $deployed = @(Copy-BranchProtectionTask -Mode 'Global' -TemplatesRoot $TemplatesRoot -TargetRoot $target -Enabled -IsDryRun)
        $deployed.Count | Should Be 1
        Test-Path $target | Should Be $false
    }

    It "copies the spec into <target>/scheduled-tasks/check-branch-protection/" {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-apply-" + [guid]::NewGuid().ToString('N'))
        try {
            $deployed = @(Copy-BranchProtectionTask -Mode 'Global' -TemplatesRoot $TemplatesRoot -TargetRoot $target -Enabled)
            $deployed.Count | Should Be 1
            Test-Path $deployed[0] | Should Be $true
            $expected = Join-Path (Join-Path (Join-Path $target "scheduled-tasks") "check-branch-protection") "check-branch-protection.md"
            $deployed[0] | Should Be $expected
        } finally {
            if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }
}
