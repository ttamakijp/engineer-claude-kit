# mcp-metrics.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/mcp-metrics.ps1 (ADR-0016 decision C) and the schema extension in
# lib/baseline-io.ps1. usage-insights.ps1 is dot-sourced once at file scope; its
# main body is guarded by `$MyInvocation.InvocationName -ne '.'`, so loading it
# runs no analysis and the real ~/.claude/projects/ tree is never read.
#
# The regression these tests pin down: before this change the aggregation looked
# only at Agent / Task launches, so a window containing nine mcp__local-llm__*
# calls reported "delegation 0%". The measured 7-day window behind snapshot 3
# held 5 generate_commit_message, 2 chat and 2 health calls, and the metric saw
# none of them.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "usage-insights.ps1"
. $ScriptPath

$script:NowUtc = (Get-Date).ToUniversalTime()

# Tool names as the server actually emits them: mcp__<server>__local_llm__<tool>.
# The server segment is user configuration, so the tests use a name that differs
# from the author's to prove nothing is pinned to it.
$script:LlmCommit = 'mcp__my-llm__local_llm__generate_commit_message'
$script:LlmChat   = 'mcp__my-llm__local_llm__chat'
$script:LlmHealth = 'mcp__my-llm__local_llm__health'

function New-McpRow {
    param(
        [string]$Kind = 'assistant',
        [string]$ToolName = '',
        [string]$SubagentType = '',
        [string]$Model = '',
        [int]$ResultChars = 0,
        [string]$Cwd = 'C:\work\proj-a',
        [int]$OffsetSeconds = 0
    )
    return [PSCustomObject]@{
        Role         = 'meta'
        Kind         = $Kind
        Timestamp    = $script:NowUtc.AddSeconds($OffsetSeconds)
        SessionId    = 's1'
        Cwd          = $Cwd
        RequestId    = 'r1'
        BlockIndex   = 0
        IsSidechain  = $false
        BlockType    = $(if ($ToolName) { 'tool_use' } else { 'text' })
        ToolName     = $ToolName
        SubagentType = $SubagentType
        BashCommand  = ''
        TextHead     = ''
        Model        = $Model
        IsUserPrompt = $false
        ResultChars  = $ResultChars
    }
}

Describe "lib/mcp-metrics.ps1 loads" {
    It "defines the public functions" {
        (Get-Command Get-McpDelegationStats -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Format-McpDelegationLines -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Add-RuleMetricsMcpStats -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Get-McpShortToolName" {
    It "strips the server segment so baselines compare across machines" {
        Get-McpShortToolName -ToolName $script:LlmChat | Should Be 'chat'
        Get-McpShortToolName -ToolName $script:LlmCommit | Should Be 'generate_commit_message'
    }
    It "leaves a non-local-llm tool name alone" {
        Get-McpShortToolName -ToolName 'Bash' | Should Be 'Bash'
    }
}

Describe "Get-McpDelegationStats counting" {
    It "counts work calls and keeps health probes out of the work total" {
        $rows = @(
            (New-McpRow -ToolName $script:LlmCommit),
            (New-McpRow -ToolName $script:LlmCommit),
            (New-McpRow -ToolName $script:LlmChat),
            (New-McpRow -ToolName $script:LlmHealth),
            (New-McpRow -ToolName $script:LlmHealth)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationLocalLlm | Should Be 3
        $s.DelegationLocalLlmProbes | Should Be 2
    }
    It "breaks the work calls down by tool" {
        $rows = @(
            (New-McpRow -ToolName $script:LlmCommit),
            (New-McpRow -ToolName $script:LlmCommit),
            (New-McpRow -ToolName $script:LlmChat)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationLocalLlmByTool['generate_commit_message'] | Should Be 2
        $s.DelegationLocalLlmByTool['chat'] | Should Be 1
    }
    It "ignores an unrelated MCP server" {
        $rows = @((New-McpRow -ToolName 'mcp__github__get_file_contents'))
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationLocalLlm | Should Be 0
    }
    It "returns zeroed counters rather than null for an empty window" {
        $s = Get-McpDelegationStats -Entries @()
        $s.DelegationLocalLlm | Should Be 0
        $s.DelegationLocalLlmProbes | Should Be 0
        $s.DelegationDisplaced.Local | Should Be 0
    }
    It "ignores rows of any other Role so the full entry array is safe to pass" {
        $rows = @(
            (New-McpRow -ToolName $script:LlmChat),
            ([PSCustomObject]@{ Role = 'assistant'; ToolName = $script:LlmChat })
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationLocalLlm | Should Be 1
    }
    It "narrows to one repository with -ProjectFilter" {
        $rows = @(
            (New-McpRow -ToolName $script:LlmChat -Cwd 'C:\work\proj-a'),
            (New-McpRow -ToolName $script:LlmChat -Cwd 'C:\work\proj-b')
        )
        $s = Get-McpDelegationStats -Entries $rows -ProjectFilter 'proj-b'
        $s.DelegationLocalLlm | Should Be 1
    }
}

Describe "Get-McpDelegationStats handler mix" {
    It "attributes a local-llm call to Local" {
        $s = Get-McpDelegationStats -Entries @((New-McpRow -ToolName $script:LlmCommit))
        $s.DelegationDisplaced.Local | Should Be 1
    }
    It "attributes a Haiku sub-agent launch to Haiku" {
        $rows = @((New-McpRow -ToolName 'Task' -SubagentType 'log-summary'))
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationDisplaced.Haiku | Should Be 1
        $s.DelegationDisplaced.Local | Should Be 0
    }
    # The bucket local-llm is meant to drain: a large output nobody was handed.
    It "attributes an absorbed large output to the family of the asking turn" {
        $rows = @(
            (New-McpRow -Model 'claude-opus-5' -OffsetSeconds 0),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 1)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationDisplaced.Opus | Should Be 1
    }
    It "separates a Sonnet turn from an Opus turn" {
        $rows = @(
            (New-McpRow -Model 'claude-sonnet-5' -OffsetSeconds 0),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 1)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationDisplaced.Sonnet | Should Be 1
        $s.DelegationDisplaced.Opus | Should Be 0
    }
    It "does not count a small output as absorbed work" {
        $rows = @(
            (New-McpRow -Model 'claude-opus-5' -OffsetSeconds 0),
            (New-McpRow -Kind 'user' -ResultChars 10 -OffsetSeconds 1)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationDisplaced.Opus | Should Be 0
    }
    It "files an absorbed output with no known model under Unknown" {
        $rows = @((New-McpRow -Kind 'user' -ResultChars 9000))
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationDisplaced.Unknown | Should Be 1
    }
    # The shape of the measured snapshot-3 window, in miniature.
    It "reproduces the snapshot-3 shape: local calls alongside absorbed output" {
        $rows = @(
            (New-McpRow -Model 'claude-opus-5' -OffsetSeconds 0),
            (New-McpRow -ToolName $script:LlmCommit -OffsetSeconds 1),
            (New-McpRow -ToolName $script:LlmHealth -OffsetSeconds 2),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 3),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 4)
        )
        $s = Get-McpDelegationStats -Entries $rows
        $s.DelegationLocalLlm | Should Be 1
        $s.DelegationDisplaced.Local | Should Be 1
        $s.DelegationDisplaced.Opus | Should Be 2
    }
}

Describe "Add-RuleMetricsMcpStats" {
    It "appends the local-llm fields without touching the existing rates" {
        $rows = @(
            (New-McpRow -Model 'claude-opus-5' -OffsetSeconds 0),
            (New-McpRow -ToolName $script:LlmCommit -OffsetSeconds 1),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 2)
        )
        $before = Get-RuleMetrics -Entries $rows
        $beforeRate = $before.DelegationRate
        $beforeHits = $before.DelegationHits
        $beforeElig = $before.DelegationEligible
        $after = Add-RuleMetricsMcpStats -Metrics (Get-RuleMetrics -Entries $rows) -Entries $rows
        # Redefining DelegationRate a third time would break comparison with
        # snapshot 3, so the local-llm counts live in their own fields.
        $after.DelegationRate | Should Be $beforeRate
        $after.DelegationHits | Should Be $beforeHits
        $after.DelegationEligible | Should Be $beforeElig
        $after.DelegationLocalLlm | Should Be 1
    }
    It "passes -ProjectFilter through to the local-llm counters" {
        $rows = @(
            (New-McpRow -ToolName $script:LlmChat -Cwd 'C:\work\proj-a'),
            (New-McpRow -ToolName $script:LlmChat -Cwd 'C:\work\proj-b')
        )
        $m = Add-RuleMetricsMcpStats -Metrics (Get-RuleMetrics -Entries $rows -ProjectFilter 'proj-a') `
            -Entries $rows -ProjectFilter 'proj-a'
        $m.DelegationLocalLlm | Should Be 1
    }
}

Describe "Format-McpDelegationLines" {
    It "emits nothing when the server was never used" {
        $s = Get-McpDelegationStats -Entries @((New-McpRow -ToolName 'Bash'))
        @(Format-McpDelegationLines -McpStats $s).Count | Should Be 0
    }
    It "names the tools and the handler mix when it was used" {
        $rows = @(
            (New-McpRow -Model 'claude-opus-5' -OffsetSeconds 0),
            (New-McpRow -ToolName $script:LlmCommit -OffsetSeconds 1),
            (New-McpRow -ToolName $script:LlmHealth -OffsetSeconds 2),
            (New-McpRow -Kind 'user' -ResultChars 9000 -OffsetSeconds 3)
        )
        $text = (@(Format-McpDelegationLines -McpStats (Get-McpDelegationStats -Entries $rows)) -join "`n")
        $text | Should Match 'generate_commit_message=1'
        $text | Should Match '1 health probe'
        $text | Should Match 'Local=1'
        $text | Should Match 'Opus=1'
        # The ceiling caveat must travel with the number (ADR-0016 question 3).
        $text | Should Match 'upper bound'
    }
    It "reports a probe-only window rather than staying silent" {
        $s = Get-McpDelegationStats -Entries @((New-McpRow -ToolName $script:LlmHealth))
        $text = (@(Format-McpDelegationLines -McpStats $s) -join "`n")
        $text | Should Match '0 work call'
    }
}

Describe "baseline-io.ps1 schema extension" {
    It "appends the local-llm keys after the existing ones" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("mcpb-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir "rule-metrics-baseline.json"
        $rows = @((New-McpRow -ToolName $script:LlmCommit))
        $m = Add-RuleMetricsMcpStats -Metrics (Get-RuleMetrics -Entries $rows) -Entries $rows
        Write-RuleMetricsBaseline -Path $path -RuleMetrics $m -DateStr '2026-11-03' -NoArchive | Out-Null
        $json = Read-RuleMetricsBaseline -Path $path
        $json.PlanFirstRate | Should Not BeNullOrEmpty
        $json.DelegationLocalLlm | Should Be 1
        $json.DelegationDisplaced.Local | Should Be 1
        $names = @($json.PSObject.Properties | ForEach-Object { $_.Name })
        # Appended, not interleaved: an older reader walking the leading keys is
        # unaffected.
        $names[0] | Should Be 'RecordedOn'
        $names[$names.Count - 1] | Should Be 'DelegationDisplaced'
        Remove-Item -Recurse -Force $dir
    }
    It "omits the local-llm keys when the counters were never collected" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("mcpb-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir "rule-metrics-baseline.json"
        # A caller that never ran Add-RuleMetricsMcpStats must write the old shape,
        # so an unchanged install produces an unchanged baseline.
        Write-RuleMetricsBaseline -Path $path -RuleMetrics (Get-RuleMetrics -Entries @()) `
            -DateStr '2026-11-03' -NoArchive | Out-Null
        $json = Read-RuleMetricsBaseline -Path $path
        @($json.PSObject.Properties | Where-Object { $_.Name -eq 'DelegationLocalLlm' }).Count | Should Be 0
        Remove-Item -Recurse -Force $dir
    }
}
