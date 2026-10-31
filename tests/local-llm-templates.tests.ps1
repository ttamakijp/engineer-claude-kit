# local-llm-templates.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Lints templates/local-llm/*.md (ADR-0016, PR (b)). These prompts are consumed
# by a 7B quantised model, so the contract that matters is structural: every
# template declares which tool it targets, which model it was written for, and
# the fixed output shape the kit reads the result back as. A template that drifts
# from its tool name or loses its output skeleton fails silently at delegation
# time -- the model still answers, just not in a shape anything can parse.
#
# The prompt bodies are Japanese. A Japanese literal in a .ps1 breaks parsing
# under PS 5.1 (BOM-less file read with the host ANSI codepage), so the
# assertions here never quote the prose. Each template instead declares ASCII
# markers in its frontmatter (output_sections, contract_markers) and those are
# what this file checks.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Join-Path $here ".."
$TemplateDir = Join-Path (Join-Path $repoRoot "templates") "local-llm"
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "encoding-helper.ps1")

# README carries no frontmatter; it documents the directory.
$script:PromptFiles = @(Get-ChildItem -LiteralPath $TemplateDir -Filter "*.md" -File |
    Where-Object { $_.Name -ne 'README.md' })

Describe "templates/local-llm" {
    It "ships the three prompt templates plus a README" {
        Test-Path (Join-Path $TemplateDir "README.md") | Should Be $true
        @($script:PromptFiles).Count | Should Be 3
        foreach ($n in @('log-summary.md', 'commit-message.md', 'review-file.md')) {
            Test-Path (Join-Path $TemplateDir $n) | Should Be $true
        }
    }
    # Japanese prose read with the host ANSI codepage mojibakes and can drop
    # lines outright (ADR-0003 section C). Every reader must go through
    # Read-Utf8NoBom, so the files must be valid UTF-8 without a BOM.
    It "stores every template as UTF-8 without a BOM" {
        foreach ($f in (Get-ChildItem -LiteralPath $TemplateDir -Filter "*.md" -File)) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            $bytes.Length | Should BeGreaterThan 0
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
            # Round-trips only if the bytes really are UTF-8.
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $text | Should Not Match "�"
        }
    }
}

Describe "templates/local-llm frontmatter" {
    It "declares the required keys in every prompt template" {
        $missing = @()
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            foreach ($key in @('target_tool', 'audience', 'description', 'model',
                               'delivery', 'output_contract', 'output_sections', 'contract_markers')) {
                if ($text -notmatch "(?m)^$key\s*:") { $missing += "$($f.Name):$key" }
            }
        }
        ($missing -join ', ') | Should Be ''
    }
    It "opens with a frontmatter delimiter" {
        foreach ($f in $script:PromptFiles) {
            $first = @((Read-Utf8NoBom -Path $f.FullName) -split "`r?`n")[0]
            $first | Should Be '---'
        }
    }
    # audience is [local-llm], deliberately NOT [claude]: these are prompts for a
    # local model, and build-rules.ps1 must never pick them up as Claude rules.
    It "uses the local-llm audience, not the Claude rule audience" {
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            $text | Should Match "(?m)^audience:\s*\[local-llm\]\s*$"
        }
    }
    It "targets a local_llm tool with no server prefix" {
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            $text | Should Match "(?m)^target_tool:\s*local_llm__\w+\s*$"
            # mcp__<server>__ is the caller-side spelling and varies per machine.
            $text | Should Not Match "(?m)^target_tool:\s*mcp__"
        }
    }
    It "names the model the prompt was written for" {
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            $text | Should Match "(?m)^model:\s*qwen"
        }
    }
    It "gives each template a distinct target tool" {
        $tools = @()
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            if ($text -match "(?m)^target_tool:\s*(\S+)") { $tools += $Matches[1] }
        }
        @($tools).Count | Should Be 3
        @($tools | Sort-Object -Unique).Count | Should Be 3
    }
    It "declares a positive output_sections count" {
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            $text | Should Match "(?m)^output_sections:\s*[1-9]\d*\s*$"
        }
    }
}

Describe "templates/local-llm output contracts" {
    # The failure mode that matters most on a small model: inventing a rationale
    # that is not in the diff or the log. Every template must forbid it.
    It "carries the no-invention marker in every template" {
        foreach ($f in $script:PromptFiles) {
            $text = Read-Utf8NoBom -Path $f.FullName
            $text | Should Match "(?m)^contract_markers:\s*\[.*\bno-invention\b.*\]\s*$"
        }
    }
    # The review pass must not hand back rewritten code, and must not edit:
    # a 7B model has no repo-wide context and does not know this kit's rules.
    It "forbids the review template from rewriting or editing" {
        $text = Read-Utf8NoBom -Path (Join-Path $TemplateDir "review-file.md")
        $text | Should Match "(?m)^contract_markers:\s*\[.*\bno-rewrite\b.*\]\s*$"
        $text | Should Match "(?m)^contract_markers:\s*\[.*\bno-edit\b.*\]\s*$"
    }
    # Footers (Co-Authored-By / Refs) are the main agent's to add.
    It "forbids the commit template from writing footers" {
        $text = Read-Utf8NoBom -Path (Join-Path $TemplateDir "commit-message.md")
        $text | Should Match "(?m)^contract_markers:\s*\[.*\bno-footer\b.*\]\s*$"
    }
    # Section headings are the parse contract; the review template's are ASCII.
    It "keeps the three categories of the file review" {
        $text = Read-Utf8NoBom -Path (Join-Path $TemplateDir "review-file.md")
        foreach ($h in @('## security', '## quality', '## style')) {
            $text | Should Match ([regex]::Escape($h))
        }
    }
    It "lists the Conventional Commits types in the commit template" {
        $text = Read-Utf8NoBom -Path (Join-Path $TemplateDir "commit-message.md")
        foreach ($t in @('feat', 'fix', 'docs', 'refactor', 'chore', 'revert')) {
            $text | Should Match ([regex]::Escape("``$t``"))
        }
    }
    # output_sections must match the skeleton the template actually shows, or the
    # declared contract and the prompt disagree. The skeletons are fenced blocks.
    It "declares as many sections as the log-summary skeleton shows" {
        $text = Read-Utf8NoBom -Path (Join-Path $TemplateDir "log-summary.md")
        $declared = 0
        if ($text -match "(?m)^output_sections:\s*(\d+)") { $declared = [int]$Matches[1] }
        $declared | Should Be 4
        # Count level-2 headings inside fenced blocks only.
        $inFence = $false; $found = 0
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '^```') { $inFence = -not $inFence; continue }
            if ($inFence -and $line -match '^## ') { $found++ }
        }
        # The skeleton plus one worked example, so each section appears twice.
        $found | Should Be ($declared * 2)
    }
}
