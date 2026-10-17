#requires -Version 5.1
# project-mix.ps1
# Provides: which projects supplied the activity in an insights window.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0015 section E.
#
# Functions:
#   Get-ProjectMix          - rows and prompts per project (session Cwd)
#   Format-ProjectMixSection - render the mix as a Markdown section
#
# Why this exists:
# The rule-firing metrics aggregate every session under ~/.claude/projects/, so
# they report a single all-projects average. That makes a shift in WHO did the
# work indistinguishable from a change in adherence. In the 2026-10-16 window two
# unrelated repositories supplied about 90% of the rows while this kit supplied
# 3.3%, and the resulting swing was first read as a regression. Publishing the
# mix next to the rates makes that confound visible instead of silent.
#
# Dependencies: none beyond the meta rows produced by
# Get-InsightsScope -IncludeRuleMetrics.

function Get-ProjectMix {
    # Aggregate meta rows by session working directory.
    #
    # Returns an array of PSCustomObject (Project, Rows, Prompts, RowShare),
    # ordered by Rows descending. Rows with no Cwd are grouped under '(unknown)'
    # rather than dropped, so the shares always add up.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Entries
    )

    $meta = @($Entries | Where-Object { $_.Role -eq 'meta' })
    if ($meta.Count -eq 0) { return @() }

    $byProject = @{}
    foreach ($row in $meta) {
        $key = [string]$row.Cwd
        if (-not $key) { $key = '(unknown)' }
        if (-not $byProject.ContainsKey($key)) {
            $byProject[$key] = [ordered]@{ Rows = 0; Prompts = 0 }
        }
        $byProject[$key].Rows += 1
        if ($row.IsUserPrompt) { $byProject[$key].Prompts += 1 }
    }

    $total = $meta.Count
    $out = @()
    foreach ($key in $byProject.Keys) {
        $bucket = $byProject[$key]
        $out += [PSCustomObject]@{
            Project  = $key
            Rows     = $bucket.Rows
            Prompts  = $bucket.Prompts
            RowShare = [math]::Round(100.0 * $bucket.Rows / $total, 1)
        }
    }
    return @($out | Sort-Object Rows -Descending)
}

function Format-ProjectMixSection {
    # Render the mix, plus a warning when a single project dominates the window.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Mix,
        [int]$Top = 8,
        [double]$DominanceThreshold = 60.0
    )

    $items = @($Mix)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## Activity by project")
    [void]$sb.AppendLine("")

    if ($items.Count -eq 0) {
        [void]$sb.AppendLine("- No transcript rows in scope.")
        [void]$sb.AppendLine("")
        return $sb.ToString()
    }

    [void]$sb.AppendLine("| Project | Rows | Share | User prompts |")
    [void]$sb.AppendLine("|---|--:|--:|--:|")
    foreach ($item in ($items | Select-Object -First $Top)) {
        $name = ($item.Project -replace '\|', '\|')
        [void]$sb.AppendLine("| $name | $($item.Rows) | $($item.RowShare)% | $($item.Prompts) |")
    }
    if ($items.Count -gt $Top) {
        [void]$sb.AppendLine("| (+$($items.Count - $Top) more) | | | |")
    }
    [void]$sb.AppendLine("")

    $lead = $items[0]
    if ($lead.RowShare -ge $DominanceThreshold) {
        [void]$sb.AppendLine("One project supplied $($lead.RowShare)% of this window, so the rule")
        [void]$sb.AppendLine("adherence rates above describe mostly that project's work. Compare rates")
        [void]$sb.AppendLine("across windows only when this mix is similar, or narrow the aggregation")
        [void]$sb.AppendLine("with Get-RuleMetrics -ProjectFilter <path>.")
        [void]$sb.AppendLine("")
    }
    return $sb.ToString()
}
