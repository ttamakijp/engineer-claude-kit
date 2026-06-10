# kit-updater.tests.ps1
# Pester v3.4 tests (Windows PowerShell 5.1 + PS 7). ASCII only.
#
# The real `git` executable is never invoked here. Test-KitBehind and
# Invoke-KitUpdate expose scriptblock injection points (-FetchAction /
# -BranchResolver / -BehindCounter / -GitRunner) so the control flow is driven
# deterministically. This mirrors the kit's testing convention (see
# cleanup-processes.ps1) because native-command mocking is unreliable under
# Pester 3.4 on Windows PowerShell 5.1. See ADR-0013.
#
# The script is dot-sourced ONCE at file scope; re-sourcing inside an It would
# redefine the functions and defeat the injection.

# $PSScriptRoot can be empty when Invoke-Pester is given a direct file path
# (vs a directory). Fall back to MyInvocation, then the current location.
$here = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$ScriptPath = Join-Path (Join-Path (Join-Path (Join-Path $here "..") "scripts") "lib") "kit-updater.ps1"

. $ScriptPath

# A throwaway directory that actually contains a .git marker so the
# Test-Path (.git) guard passes without touching a real repo. Created lazily
# per Describe via a temp folder.
function New-FakeKitRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("kit-updater-test-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $root ".git") | Out-Null
    return $root
}

Describe "kit-updater.ps1 loads" {

    It "exists" {
        Test-Path $ScriptPath | Should Be $true
    }

    It "parses without syntax errors" {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should Be 0
    }

    It "defines the public functions (dot-sourcing runs nothing)" {
        (Get-Command Test-KitBehind -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        (Get-Command Invoke-KitUpdate -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
    }
}

Describe "Test-KitBehind" {

    It "returns -1 when the path is not a git checkout (no .git)" {
        $nonRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("kit-updater-nogit-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $nonRepo | Out-Null
        try {
            Test-KitBehind -KitRoot $nonRepo | Should Be -1
        } finally {
            Remove-Item -Recurse -Force $nonRepo -ErrorAction SilentlyContinue
        }
    }

    It "returns 0 when the checkout is up to date" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) 'main' } `
                -BehindCounter { param($r, $b) '0' }
            $result | Should Be 0
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "returns the behind count when the checkout is behind" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) 'main' } `
                -BehindCounter { param($r, $b) '5' }
            $result | Should Be 5
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "returns -1 when the fetch fails or times out" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $false } `
                -BranchResolver { param($r) 'main' } `
                -BehindCounter { param($r, $b) '5' }
            $result | Should Be -1
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "returns -1 when the branch cannot be resolved" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) '' } `
                -BehindCounter { param($r, $b) '5' }
            $result | Should Be -1
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "returns -1 when the behind count is blank (git error)" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) 'main' } `
                -BehindCounter { param($r, $b) '' }
            $result | Should Be -1
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "returns -1 when a git step throws" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) throw 'boom' } `
                -BehindCounter { param($r, $b) '5' }
            $result | Should Be -1
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "trims whitespace around the branch and behind output" {
        $root = New-FakeKitRoot
        try {
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) "  main`n" } `
                -BehindCounter { param($r, $b) " 3 " }
            $result | Should Be 3
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }

    It "passes the resolved branch name to the behind counter" {
        $root = New-FakeKitRoot
        try {
            $script:seenBranch = $null
            $result = Test-KitBehind -KitRoot $root `
                -FetchAction { param($r, $t) $true } `
                -BranchResolver { param($r) 'feature/x' } `
                -BehindCounter { param($r, $b) $script:seenBranch = $b; '2' }
            $result | Should Be 2
            $script:seenBranch | Should Be 'feature/x'
        } finally {
            Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-KitUpdate" {

    It "runs a fast-forward pull by default" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' `
            -BranchResolver { param($r) 'main' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Match 'pull --ff-only origin main'
    }

    It "does not hard-reset on a default (non-force) update" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' `
            -BranchResolver { param($r) 'main' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Not Match 'reset --hard'
    }

    It "hard-resets to origin when -Force is passed" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' -Force `
            -BranchResolver { param($r) 'main' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Match 'reset --hard origin/main'
    }

    It "fetches before hard-resetting on -Force" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' -Force `
            -BranchResolver { param($r) 'main' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Match 'fetch origin'
    }

    It "does not pull when -Force is passed" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' -Force `
            -BranchResolver { param($r) 'main' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Not Match 'pull --ff-only'
    }

    It "uses the resolved branch name in the pull args" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' `
            -BranchResolver { param($r) 'develop' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } | Out-Null
        ($script:calls -join '|') | Should Match 'pull --ff-only origin develop'
    }

    It "skips the update when the branch cannot be resolved" {
        $script:calls = @()
        Invoke-KitUpdate -KitRoot 'C:\fake\kit' `
            -BranchResolver { param($r) '' } `
            -GitRunner { param($gitArgs) $script:calls += ,(@($gitArgs) -join ' ') } -WarningAction SilentlyContinue | Out-Null
        $script:calls.Count | Should Be 0
    }
}
