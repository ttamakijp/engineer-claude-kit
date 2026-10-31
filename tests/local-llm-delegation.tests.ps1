# local-llm-delegation.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Pins the contract of config/local-llm-delegation.yaml and the CLAUDE.md section
# that reads it (ADR-0016).
#
# The defect these guard against: delegating to a tool that takes its input
# inline. The only reason to delegate at all is to keep a large input out of the
# main context, so a destination that must be handed the text first saves
# nothing -- that is exactly why Haiku sub-agent delegation measured as a loss
# ($0.082-0.120 per call vs $0.023-0.060 writing it directly). The local-llm
# repo states the same rule in its own design doc: pass a path and let the
# server read it.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Join-Path $here ".."
$ConfigPath = Join-Path (Join-Path $repoRoot "config") "local-llm-delegation.yaml"
$ClaudeMd = Join-Path (Join-Path $repoRoot "templates") "CLAUDE.md"
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "encoding-helper.ps1")
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "models-config.ps1")

Describe "config/local-llm-delegation.yaml" {
    It "exists and parses with the kit's own reader" {
        Test-Path $ConfigPath | Should Be $true
        $cfg = Read-ConfigYaml -Path $ConfigPath
        $cfg | Should Not BeNullOrEmpty
        $cfg.ContainsKey('delegation') | Should Be $true
    }
    It "defines the three delegation targets" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        foreach ($k in @('commit_msg', 'log_summary', 'lint_fix')) {
            $text | Should Match "(?m)^\s+$k\s*:"
        }
    }
    # The whole point of the config. A destination that takes the body inline
    # cannot exclude the input, so it must not be listed as an mcp_tool.
    It "never routes delegation to an inline-input tool" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        $toolLines = @($text -split "`r?`n" | Where-Object { $_ -match '^\s*mcp_tool\s*:' })
        @($toolLines).Count | Should BeGreaterThan 0
        foreach ($line in $toolLines) {
            $line | Should Not Match 'local_llm__chat\s*$'
            $line | Should Not Match 'local_llm__complete\s*$'
        }
    }
    It "declares a path-shaped input for every target" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        $inputs = @($text -split "`r?`n" | Where-Object { $_ -match '^\s*input\s*:' })
        @($inputs).Count | Should Be 3
        foreach ($line in $inputs) {
            $line | Should Match 'input\s*:\s*(path|diff_path)\s*$'
        }
    }
    # fallback: self, never a Haiku sub-agent (ADR-0016 decision B).
    It "falls back to self, never to a Haiku sub-agent" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        $fallbacks = @($text -split "`r?`n" | Where-Object { $_ -match '^\s*fallback\s*:' })
        @($fallbacks).Count | Should Be 3
        foreach ($line in $fallbacks) {
            $line | Should Match 'fallback\s*:\s*self\s*$'
        }
    }
    It "keeps every system_prompt_ref kit-relative" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        $refs = @()
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '^\s*system_prompt_ref\s*:\s*(\S+)\s*$') { $refs += $Matches[1] }
        }
        @($refs).Count | Should Be 3
        foreach ($r in $refs) {
            # An absolute path would not survive a clone to another machine.
            $r | Should Not Match '^([A-Za-z]:|/|~)'
            $r | Should Match '^templates/local-llm/[a-z-]+\.md$'
        }
    }
    # Every ref must name a file that actually ships. The config and the templates
    # land in separate PRs ((a) and (b)), which is exactly how a reference goes
    # stale -- the config said lint-fix.md while (b) shipped review-file.md. The
    # check therefore runs only once the templates are present, and becomes
    # effective on the branch where both have merged.
    It "points every system_prompt_ref at a template that exists" {
        $templateDir = Join-Path (Join-Path $repoRoot "templates") "local-llm"
        $missing = @()
        # Gate on a prompt template actually being present, NOT on the directory:
        # PR (c) created templates/local-llm/ holding only a placeholder README,
        # so a directory check passes while every referenced prompt is still
        # absent, and this assertion failed on a branch that was correct.
        $prompts = @()
        if (Test-Path $templateDir) {
            $prompts = @(Get-ChildItem -LiteralPath $templateDir -Filter "*.md" -File |
                Where-Object { $_.Name -ne 'README.md' })
        }
        if (@($prompts).Count -gt 0) {
            $text = Read-Utf8NoBom -Path $ConfigPath
            foreach ($line in ($text -split "`r?`n")) {
                if ($line -match '^\s*system_prompt_ref\s*:\s*(\S+)\s*$') {
                    if (-not (Test-Path (Join-Path $repoRoot $Matches[1]))) { $missing += $Matches[1] }
                }
            }
        }
        ($missing -join ', ') | Should Be ''
    }
    It "marks every target with a known status" {
        $text = Read-Utf8NoBom -Path $ConfigPath
        $statuses = @($text -split "`r?`n" | Where-Object { $_ -match '^\s*status\s*:' })
        @($statuses).Count | Should Be 3
        foreach ($line in $statuses) {
            $line | Should Match 'status\s*:\s*(available|not_deployed)\s*$'
        }
    }
}

Describe "templates/CLAUDE.md section 3" {
    # ADR-0016 open question 5: hard-coding MCP tool names into an
    # always-loaded instruction leaves a dead instruction in every session of a
    # user who has no local-llm. The names belong in the config.
    It "names no MCP tool directly" {
        $text = Read-Utf8NoBom -Path $ClaudeMd
        $text | Should Not Match 'local_llm__'
        $text | Should Not Match 'mcp__'
    }
    It "points at the config instead" {
        $text = Read-Utf8NoBom -Path $ClaudeMd
        $text | Should Match 'local-llm-delegation\.yaml'
    }
    # PR #95 withdrew Haiku delegation; a skill or hint that still recommends it
    # contradicts the instruction the agent is given.
    It "no longer routes work to the Haiku sub-agents" {
        $text = Read-Utf8NoBom -Path $ClaudeMd
        $section3 = ($text -split '## 4\.')[0]
        $section3 | Should Not Match 'commit-msg'
        $section3 | Should Not Match 'lint-helper'
        $section3 | Should Not Match 'log-summary'
    }
}

Describe "templates/skills/commit-helper" {
    It "no longer launches the commit-msg Haiku sub-agent" {
        $skill = Join-Path (Join-Path (Join-Path (Join-Path $repoRoot "templates") "skills") "commit-helper") "SKILL.md"
        $text = Read-Utf8NoBom -Path $skill
        $text | Should Not Match 'Task tool'
        $text | Should Match 'local-llm-delegation\.yaml'
    }
}
