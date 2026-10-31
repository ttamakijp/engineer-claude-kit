# build-rules.tests.ps1
# Pester v3.4 smoke tests for scripts/build-rules.ps1 (Windows PowerShell 5.1).
# ASCII only.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path $here "..") "scripts") "build-rules.ps1"
$SourceDir = Join-Path (Join-Path (Join-Path $here "..") "source") "rules"
$TempDist = Join-Path $env:TEMP "engineer-claude-kit-test-dist"
if (Test-Path $TempDist) {
    Remove-Item -Recurse -Force $TempDist
}

Describe "build-rules.ps1" {
    It "exists and is executable" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "runs in dry-run mode without writing files" {
        $output = & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist `
            -DryRun 2>&1
        Test-Path $TempDist | Should Be $false
        ($output -join "`n") | Should Match "dry-run"
    }

    It "builds at least one rule from source" {
        & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist 2>&1 | Out-Null
        Test-Path $TempDist | Should Be $true
        $built = Get-ChildItem -Path $TempDist -Filter "*.md" -File
        $built.Count | Should BeGreaterThan 0
    }

    It "writes commit-convention.md" {
        $out = Join-Path $TempDist "commit-convention.md"
        Test-Path $out | Should Be $true
    }

    # Frontmatter contract (ADR-0015 step 1). Claude Code reads only 'paths' from a
    # rule and ignores every other key. The build copies frontmatter verbatim, so
    # 'paths' must survive to the dist file or path scoping silently stops working.
    It "preserves the paths frontmatter block in built output" {
        $out = Join-Path $TempDist "security-mobile.md"
        $text = [System.IO.File]::ReadAllText($out)
        $text | Should Match "(?m)^paths:"
        $text | Should Match "AndroidManifest"
    }

    It "keeps a rule without paths unconditional" {
        $out = Join-Path $TempDist "commit-convention.md"
        $text = [System.IO.File]::ReadAllText($out)
        ($text -match "(?m)^paths:") | Should Be $false
    }

    # Legacy keys (applyTo / priority / tags / title / description) were never read
    # by Claude Code nor by this kit. They are removed so frontmatter carries only
    # what is actually consumed: 'id' (dist filename) and 'audience' (build filter).
    It "carries no legacy frontmatter keys in any built rule" {
        $offenders = @()
        foreach ($f in (Get-ChildItem -Path $TempDist -Filter "*.md" -File)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            if ($text -match "(?m)^(applyTo|priority|tags|title|description):") {
                $offenders += $f.Name
            }
        }
        ($offenders -join ",") | Should Be ""
    }

    # Counts the sources that opt in rather than every file on disk: a rule can be
    # held back deliberately by leaving 'claude' out of its audience, and the old
    # all-files assertion read that as a build failure.
    It "builds every source rule whose audience includes claude" {
        $optIn = 0
        foreach ($f in (Get-ChildItem -Path $SourceDir -Recurse -Filter "*.md" -File)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            if ($text -match "(?m)^audience:.*\bclaude\b") { $optIn++ }
        }
        $optIn | Should BeGreaterThan 0
        $builtCount = (Get-ChildItem -Path $TempDist -Filter "*.md" -File).Count
        $builtCount | Should Be $optIn
    }

    # ADR-0016 note 3: the fallback rule is kept in the repo but not distributed,
    # because local-llm has not failed once yet and an always-loaded instruction
    # for an unobserved fault would both contradict ADR-0015 and move the
    # instruction-surface figure that snapshot 4 is meant to measure.
    It "holds the local-llm fallback rule back from the distribution" {
        Test-Path (Join-Path $TempDist "local-llm-fallback.md") | Should Be $false
    }

    # Regression (2026-10-31): the dist dir is a build output, not an
    # accumulator. apply deploys every *.md it finds there, so a rule the build
    # stopped emitting kept being installed: local-llm-fallback.md reached
    # ~/.claude/rules/ despite 'audience: [kit]' because an earlier build, from
    # before the audience change, had already written it to dist. Suppressing it
    # at the source filter is not enough -- the previous output has to go.
    It "removes a dist rule that this build no longer produces" {
        $optedOut = Join-Path $TempDist "local-llm-fallback.md"
        $deletedSource = Join-Path $TempDist "project-skill-recommend.md"
        Set-Content -LiteralPath $optedOut -Value "stale: audience dropped claude" -Encoding ASCII
        Set-Content -LiteralPath $deletedSource -Value "stale: source file deleted" -Encoding ASCII

        $output = & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist 2>&1

        Test-Path $optedOut | Should Be $false
        Test-Path $deletedSource | Should Be $false
        Test-Path (Join-Path $TempDist "commit-convention.md") | Should Be $true
        ($output -join "`n") | Should Match "\[clean\] removed stale"

        # The count is what apply actually deploys, and it is what went wrong on
        # the real machine: 6 rules installed where 5 were built.
        $optIn = 0
        foreach ($f in (Get-ChildItem -Path $SourceDir -Recurse -Filter "*.md" -File)) {
            $text = [System.IO.File]::ReadAllText($f.FullName)
            if ($text -match "(?m)^audience:.*\bclaude\b") { $optIn++ }
        }
        (Get-ChildItem -Path $TempDist -Filter "*.md" -File).Count | Should Be $optIn
    }

    It "reports a stale dist rule in dry-run mode without deleting it" {
        $optedOut = Join-Path $TempDist "local-llm-fallback.md"
        Set-Content -LiteralPath $optedOut -Value "stale" -Encoding ASCII

        $output = & powershell -NoProfile -File $ScriptPath `
            -SourceDir $SourceDir `
            -DistDir $TempDist `
            -DryRun 2>&1

        Test-Path $optedOut | Should Be $true
        ($output -join "`n") | Should Match "\[dry-run\] remove stale"
        Remove-Item -LiteralPath $optedOut -Force
    }
}

if (Test-Path $TempDist) {
    Remove-Item -Recurse -Force $TempDist
}
