# rule-metrics.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/rule-metrics.ps1 (ADR-0015 section E) plus the non-breaking
# -IncludeRuleMetrics extension of Get-InsightsScope. usage-insights.ps1 is
# dot-sourced once at file scope; its main body is guarded by
# `$MyInvocation.InvocationName -ne '.'`, so loading it runs no analysis and the
# real ~/.claude/projects/ tree is never read.
#
# Non-ASCII fixture text is built from code points so this file stays ASCII while
# still exercising multi-byte UTF-8 decoding (ADR-0003 section C).

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "usage-insights.ps1"
. $ScriptPath

$script:NowUtc = (Get-Date).ToUniversalTime()
$script:LF = [string][char]10

function Format-Utc2 {
    param([datetime]$Dt)
    return $Dt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

function New-MetaRow {
    # Build one Role='meta' row directly, bypassing JSONL, so a metric can be
    # driven from an exact block sequence.
    param(
        [string]$Kind = 'assistant',
        [string]$Sid = 's1',
        [string]$RequestId = 'r1',
        [int]$BlockIndex = 0,
        [string]$BlockType = '',
        [string]$ToolName = '',
        [string]$SubagentType = '',
        [string]$BashCommand = '',
        [switch]$IsUserPrompt,
        [int]$ResultChars = 0,
        [int]$OffsetSeconds = 0
    )
    return [PSCustomObject]@{
        Role         = 'meta'
        Kind         = $Kind
        Timestamp    = $script:NowUtc.AddSeconds($OffsetSeconds)
        SessionId    = $Sid
        RequestId    = $RequestId
        BlockIndex   = $BlockIndex
        IsSidechain  = $false
        BlockType    = $BlockType
        ToolName     = $ToolName
        SubagentType = $SubagentType
        BashCommand  = $BashCommand
        TextHead     = ''
        IsUserPrompt = [bool]$IsUserPrompt
        ResultChars  = $ResultChars
    }
}

function New-MockProjects2 {
    param([string[]]$Lines)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("rm-test-" + [System.Guid]::NewGuid().ToString("N"))
    $projDir = Join-Path $root "C--mock-project"
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null
    $file = Join-Path $projDir "00000000-0000-0000-0000-000000000000.jsonl"
    # WriteAllLines is UTF-8 without a BOM on both hosts.
    [System.IO.File]::WriteAllLines($file, $Lines)
    return $root
}

Describe "lib/rule-metrics.ps1 loads" {
    It "defines the public functions" {
        (Get-Command Get-RuleMetrics -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Format-RuleMetricsSection -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Read-RuleMetricsBaseline -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Write-RuleMetricsBaseline -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command New-RuleMetricsRow -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Get-CommitSubject" {
    It "extracts a double-quoted -m subject" {
        (Get-CommitSubject -Command 'git commit -m "feat(x): add thing"') | Should Be 'feat(x): add thing'
    }
    It "extracts a single-quoted -m subject" {
        (Get-CommitSubject -Command "git commit -m 'fix: repair thing'") | Should Be 'fix: repair thing'
    }
    It "extracts the first body line of a heredoc-fed commit" {
        $parts = @('git commit -q -F - <<EOF', 'docs(adr): write it down', '', 'body line', 'EOF')
        $cmd = $parts -join $script:LF
        (Get-CommitSubject -Command $cmd) | Should Be 'docs(adr): write it down'
    }
    It "returns null when the command carries no inline subject" {
        (Get-CommitSubject -Command 'git commit --amend --no-edit') | Should BeNullOrEmpty
    }
    It "returns null for an empty command" {
        (Get-CommitSubject -Command '') | Should BeNullOrEmpty
    }
    It "returns null for a command that is not a git commit" {
        (Get-CommitSubject -Command 'git log -m "not a commit"') | Should BeNullOrEmpty
    }
    It "accepts git commit after a shell separator" {
        (Get-CommitSubject -Command 'git add . && git commit -m "chore: staged"') | Should Be 'chore: staged'
    }
    # Regression: matching the bare phrase anywhere scored a line of source code
    # as a commit subject, because a patch script's replacement text mentioned
    # 'git commit' in a comment.
    It "ignores git commit mentioned inside prose or code" {
        $parts = @(
            'python - <<PY',
            "old = \"# 'git commit --amend --no-edit' is the other form\"",
            'PY'
        )
        (Get-CommitSubject -Command ($parts -join $script:LF)) | Should BeNullOrEmpty
    }
    # Regression: an unanchored [^"] capture ran past the end of the line and
    # returned the command-substitution opener plus the whole heredoc body, so
    # conforming commits were scored as violations.
    It "reads the heredoc subject when -m opens a command substitution" {
        $parts = @(
            'git commit -q -m "$(cat <<MSG',
            'fix(metrics): stop swallowing the heredoc',
            '',
            'body text',
            'MSG',
            ')"'
        )
        $cmd = $parts -join $script:LF
        (Get-CommitSubject -Command $cmd) | Should Be 'fix(metrics): stop swallowing the heredoc'
    }
    It "never returns a multi-line subject" {
        $parts = @('git commit -F - <<EOF', 'docs: one line only', 'second line', 'EOF')
        $subject = Get-CommitSubject -Command ($parts -join $script:LF)
        $subject | Should Not Match $script:LF
    }
}

Describe "Get-RuleRate and Get-RuleVerdict" {
    It "never divides by zero" {
        (Get-RuleRate -Hits 0 -Eligible 0) | Should Be 0.0
    }
    It "rounds to one decimal" {
        (Get-RuleRate -Hits 1 -Eligible 3) | Should Be 33.3
    }
    It "reports 'not exercised' when nothing was eligible" {
        (Get-RuleVerdict -Rate 0 -Eligible 0) | Should Be 'not exercised'
    }
    It "separates met from partial from unmet" {
        (Get-RuleVerdict -Rate 90 -Eligible 10) | Should Be 'met'
        (Get-RuleVerdict -Rate 50 -Eligible 10) | Should Be 'partial'
        (Get-RuleVerdict -Rate 5  -Eligible 10) | Should Be 'unmet'
    }
}

Describe "Get-RuleMetrics M1 plan-first" {
    It "counts a turn whose text precedes the first tool as a hit" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'thinking' -OffsetSeconds 1),
            (New-MetaRow -RequestId 'r1' -BlockIndex 1 -BlockType 'text' -OffsetSeconds 2),
            (New-MetaRow -RequestId 'r1' -BlockIndex 2 -BlockType 'tool_use' -ToolName 'Bash' -OffsetSeconds 3)
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.PlanFirstEligible | Should Be 1
        $m.PlanFirstHits | Should Be 1
        $m.PlanFirstRate | Should Be 100.0
    }
    It "counts a tool-only turn as a miss" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'thinking' -OffsetSeconds 1),
            (New-MetaRow -RequestId 'r1' -BlockIndex 1 -BlockType 'tool_use' -ToolName 'Edit' -OffsetSeconds 2)
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.PlanFirstEligible | Should Be 1
        $m.PlanFirstHits | Should Be 0
        $m.PlanFirstRate | Should Be 0.0
    }
    It "excludes a hit from the strict variant when the same turn edits a file" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'text' -OffsetSeconds 1),
            (New-MetaRow -RequestId 'r1' -BlockIndex 1 -BlockType 'tool_use' -ToolName 'Write' -OffsetSeconds 2)
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.PlanFirstHits | Should Be 1
        $m.PlanFirstStrict | Should Be 0
    }
    It "ignores tool-result user rows as prompts" {
        $rows = @(
            (New-MetaRow -Kind 'user' -RequestId '' -ResultChars 100 -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'tool_use' -ToolName 'Bash' -OffsetSeconds 1)
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.PlanFirstEligible | Should Be 0
    }
}

Describe "Get-RuleMetrics M2 delegation" {
    It "counts git commit calls and large outputs as eligible" {
        $rows = @(
            (New-MetaRow -BlockType 'tool_use' -ToolName 'Bash' -BashCommand 'git commit -m "chore: x"'),
            (New-MetaRow -Kind 'user' -RequestId '' -ResultChars 12000)
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.DelegationCommitEligible | Should Be 1
        $m.DelegationLogEligible | Should Be 1
        $m.DelegationEligible | Should Be 2
        $m.DelegationHits | Should Be 0
        $m.DelegationRate | Should Be 0.0
    }
    It "counts a sub-agent launch under either tool name" {
        $rows = @(
            (New-MetaRow -BlockType 'tool_use' -ToolName 'Agent' -SubagentType 'commit-msg'),
            (New-MetaRow -BlockType 'tool_use' -ToolName 'Task'  -SubagentType 'log-summary'),
            (New-MetaRow -BlockType 'tool_use' -ToolName 'Bash'  -BashCommand 'git commit -m "chore: x"')
        )
        $m = Get-RuleMetrics -Entries $rows
        $m.DelegationHits | Should Be 2
        $m.DelegationByAgent['commit-msg'] | Should Be 1
        $m.DelegationByAgent['log-summary'] | Should Be 1
    }
    It "records a non-Haiku sub-agent separately" {
        $rows = @((New-MetaRow -BlockType 'tool_use' -ToolName 'Agent' -SubagentType 'architect'))
        $m = Get-RuleMetrics -Entries $rows
        $m.DelegationHits | Should Be 0
        $m.DelegationOther | Should Be 1
    }
    It "ignores a result below the large-output threshold" {
        $rows = @((New-MetaRow -Kind 'user' -RequestId '' -ResultChars 100))
        $m = Get-RuleMetrics -Entries $rows
        $m.DelegationLogEligible | Should Be 0
    }
}

Describe "Get-RuleMetrics M3 commit convention" {
    It "scores a conforming subject" {
        $rows = @((New-MetaRow -BlockType 'tool_use' -ToolName 'Bash' -BashCommand 'git commit -m "feat(rules): add paths"'))
        $m = Get-RuleMetrics -Entries $rows
        $m.CommitTotal | Should Be 1
        $m.CommitExtracted | Should Be 1
        $m.CommitConforming | Should Be 1
        $m.CommitRate | Should Be 100.0
    }
    It "scores a non-conforming subject and samples it" {
        $rows = @((New-MetaRow -BlockType 'tool_use' -ToolName 'Bash' -BashCommand 'git commit -m "updated some files"'))
        $m = Get-RuleMetrics -Entries $rows
        $m.CommitConforming | Should Be 0
        @($m.CommitOffenders).Count | Should Be 1
    }
    It "counts a subject-less commit as unextractable, not as a failure" {
        $rows = @((New-MetaRow -BlockType 'tool_use' -ToolName 'Bash' -BashCommand 'git commit --amend --no-edit'))
        $m = Get-RuleMetrics -Entries $rows
        $m.CommitTotal | Should Be 1
        $m.CommitExtracted | Should Be 0
        $m.CommitRate | Should Be 0.0
    }
}

Describe "Get-RuleMetrics with no data" {
    It "flags itself unavailable rather than reporting 0 percent adherence" {
        $m = Get-RuleMetrics -Entries @()
        $m.Available | Should Be $false
        $m.PlanFirstEligible | Should Be 0
    }
}

Describe "Get-InsightsScope -IncludeRuleMetrics" {
    $ts = Format-Utc2 $script:NowUtc
    $prompt = @{ type = 'user'; timestamp = $ts; sessionId = 's1'; message = @{ content = 'plain ascii prompt' } } | ConvertTo-Json -Compress -Depth 6
    $asst = @{
        type = 'assistant'; timestamp = $ts; sessionId = 's1'; requestId = 'req-1'; apiBlockIndex = 0
        message = @{ model = 'claude-opus-5'; usage = @{ input_tokens = 1; output_tokens = 1 }
                     content = @(@{ type = 'text'; text = 'here is the plan' }) }
    } | ConvertTo-Json -Compress -Depth 8
    $root = New-MockProjects2 -Lines @($prompt, $asst)

    It "emits no meta rows by default (existing row contract unchanged)" {
        $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc)
        (@($rows | Where-Object { $_.Role -eq 'meta' })).Count | Should Be 0
        $rows.Count | Should Be 2
    }
    It "emits meta rows when asked, leaving the assistant and user rows intact" {
        $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc -IncludeRuleMetrics)
        (@($rows | Where-Object { $_.Role -eq 'assistant' })).Count | Should Be 1
        (@($rows | Where-Object { $_.Role -eq 'user' })).Count | Should Be 1
        (@($rows | Where-Object { $_.Role -eq 'meta' })).Count | Should Be 2
    }
    It "marks a real prompt and reconstructs the turn id" {
        $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc -IncludeRuleMetrics)
        $meta = @($rows | Where-Object { $_.Role -eq 'meta' })
        (@($meta | Where-Object { $_.IsUserPrompt })).Count | Should Be 1
        (@($meta | Where-Object { $_.RequestId -eq 'req-1' })).Count | Should Be 1
    }
}

Describe "Get-InsightsScope UTF-8 decoding" {
    # Regression guard: Get-Content without -Encoding decodes with the host ANSI
    # codepage on PS 5.1, which corrupted every transcript line carrying Japanese
    # text and made ConvertFrom-Json drop it. That silently discarded most real
    # user prompts (14 detected where PS 7 saw 67) and under-counted tokens.
    $ts = Format-Utc2 $script:NowUtc
    $jp = [string]::Concat([char]0x65E5, [char]0x672C, [char]0x8A9E, [char]0x30C6, [char]0x30B9, [char]0x30C8)
    $prompt = @{ type = 'user'; timestamp = $ts; sessionId = 's2'; message = @{ content = $jp } } | ConvertTo-Json -Compress -Depth 6
    $root = New-MockProjects2 -Lines @($prompt)

    It "parses a transcript line containing multi-byte UTF-8 on every host" {
        $rows = @(Get-InsightsScope -WindowDays 7 -ProjectsRoot $root -Now $script:NowUtc -IncludeRuleMetrics)
        $meta = @($rows | Where-Object { $_.Role -eq 'meta' })
        $meta.Count | Should Be 1
        (@($meta | Where-Object { $_.IsUserPrompt })).Count | Should Be 1
    }
}

Describe "Format-RuleMetricsSection" {
    It "renders the table with a status column" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'text' -OffsetSeconds 1)
        )
        $m = Get-RuleMetrics -Entries $rows
        $text = Format-RuleMetricsSection -RuleMetrics $m
        $text | Should Match '## Rule firing metrics'
        $text | Should Match 'plan-first'
        $text | Should Match 'not exercised|met|partial|unmet'
    }
    It "says so when there is nothing in scope" {
        $m = Get-RuleMetrics -Entries @()
        $text = Format-RuleMetricsSection -RuleMetrics $m
        $text | Should Match 'metrics unavailable'
    }
    It "adds a delta when a baseline is supplied" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'text' -OffsetSeconds 1)
        )
        $m = Get-RuleMetrics -Entries $rows
        $baseline = [PSCustomObject]@{ PlanFirstRate = 40.0; DelegationRate = 0.0; CommitRate = 0.0 }
        $text = Format-RuleMetricsSection -RuleMetrics $m -Baseline $baseline
        $text | Should Match '\+60 pt'
    }
}

Describe "rule-metrics baseline round-trip" {
    It "returns null for a missing baseline" {
        (Read-RuleMetricsBaseline -Path (Join-Path $env:TEMP "no-such-baseline-xyz.json")) | Should BeNullOrEmpty
    }
    It "writes and reads back the stored rates" {
        $rows = @(
            (New-MetaRow -Kind 'user' -IsUserPrompt -RequestId '' -OffsetSeconds 0),
            (New-MetaRow -RequestId 'r1' -BlockIndex 0 -BlockType 'text' -OffsetSeconds 1)
        )
        $m = Get-RuleMetrics -Entries $rows
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("rm-baseline-" + [System.Guid]::NewGuid().ToString("N") + ".json")
        $written = Write-RuleMetricsBaseline -Path $path -RuleMetrics $m -DateStr '2026-10-06' -WindowDays 7
        Test-Path $written | Should Be $true
        $back = Read-RuleMetricsBaseline -Path $path
        $back.RecordedOn | Should Be '2026-10-06'
        $back.PlanFirstRate | Should Be 100.0
        Remove-Item -Force $path
    }
}
