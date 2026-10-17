# project-mix.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/project-mix.ps1 (ADR-0015 section E). The rule-firing rates are an
# all-projects average, so a window where one repository dominates cannot be
# told apart from a real change in adherence. These tests pin the breakdown that
# makes that confound visible.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
. (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "lib") "project-mix.ps1")

function New-MixRow {
    param([string]$Cwd, [switch]$IsUserPrompt)
    return [PSCustomObject]@{
        Role = 'meta'; Cwd = $Cwd; IsUserPrompt = [bool]$IsUserPrompt
    }
}

Describe "Get-ProjectMix" {
    It "returns empty for no rows" {
        @(Get-ProjectMix -Entries @()).Count | Should Be 0
    }
    It "ignores rows that are not meta rows" {
        $rows = @([PSCustomObject]@{ Role = 'assistant'; Cwd = 'C:\a' })
        @(Get-ProjectMix -Entries $rows).Count | Should Be 0
    }
    It "aggregates rows and prompts per project" {
        $rows = @(
            (New-MixRow -Cwd 'C:\a' -IsUserPrompt),
            (New-MixRow -Cwd 'C:\a'),
            (New-MixRow -Cwd 'C:\a'),
            (New-MixRow -Cwd 'C:\b' -IsUserPrompt)
        )
        $mix = @(Get-ProjectMix -Entries $rows)
        $mix.Count | Should Be 2
        $mix[0].Project | Should Be 'C:\a'
        $mix[0].Rows | Should Be 3
        $mix[0].Prompts | Should Be 1
        $mix[0].RowShare | Should Be 75
        $mix[1].Project | Should Be 'C:\b'
    }
    It "orders by row count descending" {
        $rows = @((New-MixRow -Cwd 'C:\small'), (New-MixRow -Cwd 'C:\big'), (New-MixRow -Cwd 'C:\big'))
        (@(Get-ProjectMix -Entries $rows))[0].Project | Should Be 'C:\big'
    }
    It "groups rows without a Cwd under (unknown) so shares still total 100" {
        $rows = @((New-MixRow -Cwd 'C:\a'), (New-MixRow -Cwd ''))
        $mix = @(Get-ProjectMix -Entries $rows)
        $mix.Count | Should Be 2
        (($mix | ForEach-Object { $_.RowShare }) | Measure-Object -Sum).Sum | Should Be 100
        ($mix | Where-Object { $_.Project -eq '(unknown)' }).Rows | Should Be 1
    }
}

Describe "Format-ProjectMixSection" {
    It "says so when nothing is in scope" {
        (Format-ProjectMixSection -Mix @()) | Should Match 'No transcript rows in scope'
    }
    It "renders a row per project" {
        $mix = @(Get-ProjectMix -Entries @((New-MixRow -Cwd 'C:\only' -IsUserPrompt)))
        $text = Format-ProjectMixSection -Mix $mix
        $text | Should Match '## Activity by project'
        # Match on the leaf only: a Windows path in a regex needs escaping and
        # adds nothing to what this test checks.
        $text | Should Match 'only'
    }
    # The 2026-10-16 window had two unrelated repositories at ~90% of the rows
    # while this kit supplied 3.3%; the swing was first read as a regression.
    It "warns when one project dominates the window" {
        $rows = @()
        1..9 | ForEach-Object { $rows += (New-MixRow -Cwd 'C:\dominant') }
        $rows += (New-MixRow -Cwd 'C:\minor')
        $text = Format-ProjectMixSection -Mix (Get-ProjectMix -Entries $rows)
        $text | Should Match 'supplied 90% of this window'
        $text | Should Match 'ProjectFilter'
    }
    It "stays quiet when the mix is balanced" {
        $rows = @((New-MixRow -Cwd 'C:\a'), (New-MixRow -Cwd 'C:\b'))
        $text = Format-ProjectMixSection -Mix (Get-ProjectMix -Entries $rows)
        $text | Should Not Match 'of this window'
    }
    It "truncates the table and reports the remainder" {
        $rows = @()
        1..10 | ForEach-Object { $rows += (New-MixRow -Cwd ("C:\p$_")) }
        $text = Format-ProjectMixSection -Mix (Get-ProjectMix -Entries $rows) -Top 3
        $text | Should Match '\(\+7 more\)'
    }
}
