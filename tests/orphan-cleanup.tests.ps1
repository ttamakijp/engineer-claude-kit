# orphan-cleanup.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers lib/orphan-cleanup.ps1: deploy writes what the kit ships now, so a
# payload it has STOPPED shipping has to be removed explicitly or the deployed
# copy keeps being loaded into every session. Hit twice -- ADR-0015 left a
# deleted rule in ~/.claude/rules/, and ADR-0016 decision B withdrew the three
# Haiku delegation agents whose descriptions would otherwise have stayed in the
# session's agent roster.
#
# Attribution comes from the previous run's marker: only files the kit itself
# deployed are removed, and a hand-written file is reported instead.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$KitRoot = (Resolve-Path (Join-Path $here "..")).Path
$libDir = Join-Path (Join-Path $KitRoot "scripts") "lib"
. (Join-Path $libDir "encoding-helper.ps1")
. (Join-Path $libDir "link-safety.ps1")
. (Join-Path $libDir "orphan-cleanup.ps1")

Describe "Remove-OrphanedKitFiles for the rules payload" {
    # Deploy used to be additive only. ADR-0015 deleted
    # project-skill-recommend.md, but the already-deployed copy (3,554 B, no
    # paths, so loaded unconditionally) survived the apply and kept inflating the
    # context the reduction was meant to shrink. Observed on the real machine
    # after the 2026-10-17 apply: 6 rules / 16,961 B where 5 / 13,407 B was
    # expected.

    function New-RulesFixture {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("orphan-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        return $dir
    }

    It "removes a rule the kit shipped before but no longer builds" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"
        $kept = Join-Path $rules "kept.md"
        Write-Utf8NoBom -Path $kept -Content "# current"

        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir $rules -CurrentApplied @($kept) `
            -PreviousAppliedFiles @("C:\somewhere\.claude\rules\gone.md", "C:\somewhere\.claude\rules\kept.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $orphan | Should Be $false
        Test-Path $kept | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "backs the removed rule up before deleting it" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        Write-Utf8NoBom -Path (Join-Path $rules "gone.md") -Content "# stale content"

        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        $saved = @(Get-ChildItem -LiteralPath (Join-Path $dir "backups") -Recurse -Filter "gone.md" -File)
        $saved.Count | Should BeGreaterThan 0
        (Get-Content -LiteralPath $saved[0].FullName -Raw) | Should Match 'stale content'
        Remove-Item -Recurse -Force $dir
    }
    # A hand-written rule was never in applied_files, so it must survive.
    It "never deletes a rule the kit did not deploy" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $mine = Join-Path $rules "my-own-rule.md"
        Write-Utf8NoBom -Path $mine -Content "# user authored"

        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @() -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $mine | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "matches on leaf name so a marker from another path still attributes" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"

        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("D:\OTHER\.CLAUDE\RULES\GONE.MD") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $orphan | Should Be $false
        Remove-Item -Recurse -Force $dir
    }
    It "removes nothing in dry-run mode" {
        $dir = New-RulesFixture
        $rules = Join-Path $dir "rules"
        New-Item -ItemType Directory -Force -Path $rules | Out-Null
        $orphan = Join-Path $rules "gone.md"
        Write-Utf8NoBom -Path $orphan -Content "# stale"

        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir $rules -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1" -IsDryRun

        Test-Path $orphan | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
    It "tolerates a missing rules directory" {
        $dir = New-RulesFixture
        Remove-OrphanedKitFiles -PathSegment "rules" -Kind "rule" -TargetDir (Join-Path $dir "absent") -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\gone.md")
        $true | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
}


Describe "Remove-OrphanedKitFiles for the agents payload" {
    # Same removal, one directory over. Claude Code reads every file in
    # <target>/agents/ into the session's agent roster, so an agent the kit has
    # stopped shipping keeps advertising itself -- which is what withdrawing the
    # three Haiku delegation agents (ADR-0016 decision B) had to deal with.

    function New-AgentsFixture {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("agentorphan-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path (Join-Path $dir "agents") | Out-Null
        return $dir
    }

    It "removes an agent the kit shipped before but no longer ships" {
        $dir = New-AgentsFixture
        $agents = Join-Path $dir "agents"
        $withdrawn = Join-Path $agents "commit-msg.md"
        Write-Utf8NoBom -Path $withdrawn -Content "# haiku delegation"
        $kept = Join-Path $agents "architect.md"
        Write-Utf8NoBom -Path $kept -Content "# heavy"

        Remove-OrphanedKitFiles -PathSegment "agents" -Kind "agent" -TargetDir $agents `
            -CurrentApplied @($kept) `
            -PreviousAppliedFiles @("C:\x\.claude\agents\commit-msg.md", "C:\x\.claude\agents\architect.md") `
            -BackupRoot (Join-Path $dir "backups") -BackupStamp "s1"

        Test-Path $withdrawn | Should Be $false
        Test-Path $kept | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    It "never deletes an agent the user wrote by hand" {
        $dir = New-AgentsFixture
        $agents = Join-Path $dir "agents"
        $mine = Join-Path $agents "my-own-agent.md"
        Write-Utf8NoBom -Path $mine -Content "# user authored"

        Remove-OrphanedKitFiles -PathSegment "agents" -Kind "agent" -TargetDir $agents `
            -CurrentApplied @() -PreviousAppliedFiles @()

        Test-Path $mine | Should Be $true
        Remove-Item -Recurse -Force $dir
    }

    # The marker lists every payload the run deployed, so attribution has to be
    # scoped by directory. Without -PathSegment a withdrawn RULE of the same leaf
    # name would authorise deleting an agent the kit still ships, and the other
    # way round.
    It "does not let a marker entry from another payload authorise a deletion" {
        $dir = New-AgentsFixture
        $agents = Join-Path $dir "agents"
        $target = Join-Path $agents "commit-convention.md"
        Write-Utf8NoBom -Path $target -Content "# same leaf name, different payload"

        Remove-OrphanedKitFiles -PathSegment "agents" -Kind "agent" -TargetDir $agents `
            -CurrentApplied @() `
            -PreviousAppliedFiles @("C:\x\.claude\rules\commit-convention.md")

        Test-Path $target | Should Be $true
        Remove-Item -Recurse -Force $dir
    }
}

Describe "Get-KitPreviousAppliedFiles" {

    It "reads applied_files from the marker of the previous run" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("marker-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $payload = @{ applied_files = @("C:\x\.claude\agents\gone.md", "C:\x\.claude\rules\kept.md") } |
            ConvertTo-Json -Depth 5
        Write-Utf8NoBom -Path (Join-Path $dir ".engineer-claude-kit-applied") -Content $payload

        $files = @(Get-KitPreviousAppliedFiles -MarkerRoot $dir)

        $files.Count | Should Be 2
        ($files -join ';') | Should Match 'gone\.md'
        Remove-Item -Recurse -Force $dir
    }

    # PS 5.1 hands a single-element JSON array back as one object, so a cast
    # would collapse it into one joined string and the leaf name would never
    # match.
    It "keeps a single entry a one-element list" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("marker-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Utf8NoBom -Path (Join-Path $dir ".engineer-claude-kit-applied") `
            -Content '{"applied_files":["C:/x/.claude/agents/only.md"]}'

        $files = @(Get-KitPreviousAppliedFiles -MarkerRoot $dir)

        $files.Count | Should Be 1
        (Split-Path -Leaf $files[0]) | Should Be "only.md"
        Remove-Item -Recurse -Force $dir
    }

    It "returns an empty list when there is no marker" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("marker-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        @(Get-KitPreviousAppliedFiles -MarkerRoot $dir).Count | Should Be 0
        Remove-Item -Recurse -Force $dir
    }

    # A hand-edited or truncated marker must not abort the apply: with no
    # readable record nothing is attributable, so nothing gets removed.
    It "returns an empty list when the marker is not valid JSON" {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("marker-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Utf8NoBom -Path (Join-Path $dir ".engineer-claude-kit-applied") -Content '{ truncated'

        @(Get-KitPreviousAppliedFiles -MarkerRoot $dir).Count | Should Be 0
        Remove-Item -Recurse -Force $dir
    }
}
