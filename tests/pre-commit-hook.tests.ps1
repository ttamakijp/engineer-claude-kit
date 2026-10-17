# pre-commit-hook.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# Covers templates/git-hooks/pre-commit (ADR-0015 step 6 item 6). Until now the
# kit asserted only that the hook file was copied byte-for-byte
# (project-mode.tests.ps1); nothing checked what it actually does, which is why
# the false positive on templates/.mailmap went unnoticed.
#
# The hook is bash, so each case stages a file in a throwaway git repository and
# runs the hook directly. gitleaks output is irrelevant here and is filtered out;
# the hook skips that check entirely when gitleaks is not on PATH.

$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$repoRoot = Split-Path -Parent $here
$HookPath = Join-Path (Join-Path (Join-Path $repoRoot "templates") "git-hooks") "pre-commit"
$MailmapPath = Join-Path (Join-Path $repoRoot "templates") ".mailmap"

$script:BashExe = (Get-Command bash -ErrorAction SilentlyContinue)

function Invoke-PreCommitOn {
    # Stage $Content as a file in a fresh repo, run the hook, return
    # @{ Code = <exit code>; Output = <combined output> }.
    param([string]$Content, [string]$FileName = 'staged.md', [string]$CopyFrom)

    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("pc-test-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    try {
        & git init -q $repo 2>&1 | Out-Null
        $hooksDir = Join-Path (Join-Path $repo ".git") "hooks"
        Copy-Item -LiteralPath $HookPath -Destination (Join-Path $hooksDir "pre-commit") -Force

        $target = Join-Path $repo $FileName
        if ($CopyFrom) {
            Copy-Item -LiteralPath $CopyFrom -Destination $target -Force
        } else {
            [System.IO.File]::WriteAllText($target, $Content)
        }
        & git -C $repo add -A 2>&1 | Out-Null

        Push-Location $repo
        try {
            $out = & bash (Join-Path $hooksDir "pre-commit") 2>&1
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $text = (@($out) -join "`n")
        return @{ Code = $code; Output = $text }
    } finally {
        if (Test-Path $repo) { Remove-Item -Recurse -Force $repo -ErrorAction SilentlyContinue }
    }
}

Describe "pre-commit hook: email detection" {
    if (-not $script:BashExe) {
        It "requires bash on PATH" { $script:BashExe | Should Not BeNullOrEmpty }
        return
    }

    It "exists" {
        Test-Path $HookPath | Should Be $true
    }

    # The original defect: committing the shipped .mailmap always failed, because
    # its documentation examples are email addresses and the regex did not
    # distinguish them from real ones.
    It "allows the shipped .mailmap" {
        $r = Invoke-PreCommitOn -CopyFrom $MailmapPath -FileName '.mailmap'
        $r.Code | Should Be 0
    }
    It "allows RFC 2606 example domains" {
        $r = Invoke-PreCommitOn -Content "contact: foo@example.com and bar@example.org"
        $r.Code | Should Be 0
    }
    It "allows reserved .invalid / .test domains" {
        $r = Invoke-PreCommitOn -Content "x@host.invalid y@foo.test"
        $r.Code | Should Be 0
    }
    It "allows no-reply senders" {
        $r = Invoke-PreCommitOn -Content "Co-Authored-By: Someone <noreply@anthropic.com>"
        $r.Code | Should Be 0
    }

    # Detection must survive the allowlist: path-based exclusions would have
    # stopped catching these in docs entirely.
    It "blocks a real-looking address" {
        $r = Invoke-PreCommitOn -Content "owner: someone@company.co.jp"
        $r.Code | Should Be 1
        $r.Output | Should Match 'possible email address'
    }
    It "blocks a real-looking address inside a markdown file" {
        $r = Invoke-PreCommitOn -Content "See someone@company.co.jp for details." -FileName 'README-extra.md'
        $r.Code | Should Be 1
    }
    It "names the offending address instead of only saying one exists" {
        $r = Invoke-PreCommitOn -Content "a: someone@company.co.jp"
        $r.Output | Should Match 'someone@company\.co\.jp'
    }
    It "lists each offending address once" {
        $r = Invoke-PreCommitOn -Content "a: dup@company.co.jp`nb: dup@company.co.jp"
        $r.Code | Should Be 1
        ([regex]::Matches($r.Output, 'dup@company\.co\.jp')).Count | Should Be 1
    }
    It "reports a real address even when allowlisted ones are present" {
        $r = Invoke-PreCommitOn -Content "ok: fine@example.com`nbad: someone@company.co.jp"
        $r.Code | Should Be 1
        $r.Output | Should Match 'someone@company\.co\.jp'
        $r.Output | Should Not Match 'fine@example\.com'
    }
    It "passes a diff with no addresses at all" {
        $r = Invoke-PreCommitOn -Content "just some text with no contact details"
        $r.Code | Should Be 0
    }
}

Describe "templates/.mailmap" {
    It "carries no real address in its examples" {
        $text = [System.IO.File]::ReadAllText($MailmapPath)
        $addresses = @([regex]::Matches($text, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}') |
            ForEach-Object { $_.Value })
        $addresses.Count | Should BeGreaterThan 0
        # Every example must sit on a reserved domain. This file ships in a public
        # repository, so a real address here is a leak in its own right.
        $offenders = @($addresses | Where-Object { $_ -notmatch '@example\.(com|org|net)$' })
        ($offenders -join ',') | Should Be ""
    }
}
