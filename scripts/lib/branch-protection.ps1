#requires -Version 5.1
# branch-protection.ps1
# Shared helper for the GitHub branch-protection ruleset feature.
#
# Why this exists:
#   A new repository starts with an unprotected default branch. The kit ships a
#   canonical ruleset (templates/branch-protection/protect-main.json) and this
#   helper compares a repository's live rulesets against it, so the check and
#   apply entry points stay thin wrappers over one comparison implementation.
#
# Public functions:
#   Get-RepoFromGitRemote     -- OWNER/REPO from a git remote URL
#   Read-RulesetTemplate      -- load + parse the canonical ruleset JSON
#   New-RulesetRequestBody    -- template -> POST/PUT body (drops response-only keys)
#   Invoke-GhApi              -- run `gh api ...` (injectable for tests)
#   Get-RepoRuleset           -- fetch one named ruleset with full detail, or $null
#   Compare-RulesetState      -- expected vs actual -> match / drift / missing
#   Format-RulesetReport      -- human-readable report lines
#   Copy-BranchProtectionTask -- deploy the scheduled-task spec (apply-claude-kit)
#
# Comparison policy (see docs/branch-protection.md):
#   - Rule TYPES are compared exactly in both directions (an extra rule on the
#     repository is drift).
#   - Rule PARAMETERS are compared as a subset: every parameter the template
#     declares must match, but parameters GitHub adds on its own are ignored.
#     Without this, every API-side default addition would read as drift.
#
# Dot-sourcing only loads the functions; nothing runs.
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible: no -AsHashtable, no ternary, no PS 6+ cmdlets.

function Get-RepoFromGitRemote {
    # Derive OWNER/REPO from a git remote URL. Accepts the HTTPS, SSH and
    # scp-like forms git writes. Returns $null when the URL is not a GitHub
    # remote or when git is unavailable / the path is not a repository.
    [CmdletBinding()]
    param(
        [string]$Path = ".",
        [string]$Remote = "origin",
        [string]$Url
    )

    if (-not $PSBoundParameters.ContainsKey('Url')) {
        try {
            $Url = (& git -C $Path remote get-url $Remote 2>$null | Select-Object -First 1)
        } catch {
            return $null
        }
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    if (-not $Url) { return $null }

    $trimmed = $Url.Trim()
    # Strip a trailing .git and any trailing slash before matching.
    $trimmed = $trimmed -replace '\.git/?$', ''
    $trimmed = $trimmed -replace '/$', ''

    # https://github.com/OWNER/REPO , ssh://git@github.com/OWNER/REPO ,
    # git@github.com:OWNER/REPO
    if ($trimmed -match '(?:github\.com[:/])([^/:]+)/([^/]+)$') {
        return "$($Matches[1])/$($Matches[2])"
    }
    return $null
}

function Read-RulesetTemplate {
    # Load the canonical ruleset JSON and return it as a PSCustomObject.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Ruleset template not found: $Path"
    }
    # Read-Utf8NoBom is not assumed here: this helper is dot-sourced standalone by
    # the entry scripts. The template is ASCII JSON, so Raw + ConvertFrom-Json is
    # sufficient and keeps the helper dependency-free.
    $raw = Get-Content -LiteralPath $Path -Raw
    return ($raw | ConvertFrom-Json)
}

function New-RulesetRequestBody {
    # Build the JSON body for POST / PUT from the template. `source_type` and
    # `source` are response-only fields; GitHub rejects or ignores them on write,
    # so they are dropped. Returns a compact JSON string.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Template)

    $body = [ordered]@{
        name        = $Template.name
        target      = $Template.target
        enforcement = $Template.enforcement
    }
    if ($null -ne $Template.conditions)    { $body.conditions    = $Template.conditions }
    if ($null -ne $Template.rules)         { $body.rules         = $Template.rules }
    if ($null -ne $Template.bypass_actors) { $body.bypass_actors = @($Template.bypass_actors) }

    return ($body | ConvertTo-Json -Depth 10 -Compress)
}

function Invoke-GhApi {
    # Run `gh` with the given argument list and return @{ ExitCode; Output }.
    # -Body is piped to gh's stdin (used with `--input -`).
    # -Invoker is a test injection point: { param($Arguments, $Body) ... }.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Body,
        [scriptblock]$Invoker
    )

    if ($PSBoundParameters.ContainsKey('Invoker')) {
        return (& $Invoker $Arguments $Body)
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Install it and run 'gh auth login'."
    }

    if ($Body) {
        $out = ($Body | & gh @Arguments 2>&1 | Out-String)
    } else {
        $out = (& gh @Arguments 2>&1 | Out-String)
    }
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}

function Get-RepoRuleset {
    # Return the full detail object of the ruleset named -Name on -Repo, or
    # $null when no ruleset with that name exists.
    #
    # Two calls are required: the list endpoint omits `rules` and `conditions`,
    # so the id found there is re-fetched from the detail endpoint.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [string]$Name = "protect-main",
        [scriptblock]$Invoker
    )

    $listArgs = @('api', "repos/$Repo/rulesets")
    if ($PSBoundParameters.ContainsKey('Invoker')) {
        $listed = Invoke-GhApi -Arguments $listArgs -Invoker $Invoker
    } else {
        $listed = Invoke-GhApi -Arguments $listArgs
    }
    if ($listed.ExitCode -ne 0) {
        throw "gh api repos/$Repo/rulesets failed (exit $($listed.ExitCode)): $($listed.Output)"
    }

    $rulesets = @()
    if ($listed.Output -and $listed.Output.Trim()) {
        $rulesets = @($listed.Output | ConvertFrom-Json)
    }
    $match = $rulesets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $match) { return $null }

    $detailArgs = @('api', "repos/$Repo/rulesets/$($match.id)")
    if ($PSBoundParameters.ContainsKey('Invoker')) {
        $detail = Invoke-GhApi -Arguments $detailArgs -Invoker $Invoker
    } else {
        $detail = Invoke-GhApi -Arguments $detailArgs
    }
    if ($detail.ExitCode -ne 0) {
        throw "gh api repos/$Repo/rulesets/$($match.id) failed (exit $($detail.ExitCode)): $($detail.Output)"
    }
    return ($detail.Output | ConvertFrom-Json)
}

function ConvertTo-FactValue {
    # Normalize a JSON-derived value into a stable, comparable string.
    # Arrays are sorted so member order never reads as drift.
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return "(null)" }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [string]) { return $Value }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return "[]" }
        $rendered = @()
        foreach ($item in $items) {
            if ($item -is [string] -or $item -is [ValueType]) {
                $rendered += [string]$item
            } else {
                $rendered += ($item | ConvertTo-Json -Depth 6 -Compress)
            }
        }
        return (($rendered | Sort-Object) -join ',')
    }

    if ($Value -is [psobject] -and $Value.PSObject.Properties.Name.Count -gt 0 -and
        -not ($Value -is [ValueType])) {
        return ($Value | ConvertTo-Json -Depth 6 -Compress)
    }
    return [string]$Value
}

function Get-RuleParameterMap {
    # type -> parameters (PSCustomObject or $null) for every rule in a ruleset.
    [CmdletBinding()]
    param($Ruleset)

    $map = @{}
    foreach ($rule in @($Ruleset.rules)) {
        if ($null -eq $rule) { continue }
        $map[[string]$rule.type] = $rule.parameters
    }
    return $map
}

function Compare-RulesetState {
    # Compare the expected (template) ruleset against the actual (API) one.
    # Returns @{ Status; Differences } where Status is 'missing', 'match' or
    # 'drift' and Differences is an array of human-readable lines.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Expected,
        $Actual
    )

    if ($null -eq $Actual) {
        return [PSCustomObject]@{ Status = 'missing'; Differences = @() }
    }

    $diffs = @()

    # Top-level scalars and conditions.
    $scalarChecks = @(
        @{ Key = 'enforcement'; Exp = $Expected.enforcement; Act = $Actual.enforcement },
        @{ Key = 'target';      Exp = $Expected.target;      Act = $Actual.target },
        @{ Key = 'conditions.ref_name.include'
           Exp = $Expected.conditions.ref_name.include
           Act = $Actual.conditions.ref_name.include },
        @{ Key = 'conditions.ref_name.exclude'
           Exp = $Expected.conditions.ref_name.exclude
           Act = $Actual.conditions.ref_name.exclude },
        @{ Key = 'bypass_actors'; Exp = $Expected.bypass_actors; Act = $Actual.bypass_actors }
    )
    foreach ($check in $scalarChecks) {
        $e = ConvertTo-FactValue -Value $check.Exp
        $a = ConvertTo-FactValue -Value $check.Act
        if ($e -ne $a) {
            $diffs += "$($check.Key): expected=$e actual=$a"
        }
    }

    # Rule types: exact set comparison in both directions.
    $expectedMap = Get-RuleParameterMap -Ruleset $Expected
    $actualMap   = Get-RuleParameterMap -Ruleset $Actual
    $expectedTypes = @($expectedMap.Keys | Sort-Object)
    $actualTypes   = @($actualMap.Keys | Sort-Object)
    foreach ($type in $expectedTypes) {
        if ($actualTypes -notcontains $type) { $diffs += "rules: missing rule type '$type'" }
    }
    foreach ($type in $actualTypes) {
        if ($expectedTypes -notcontains $type) { $diffs += "rules: unexpected rule type '$type'" }
    }

    # Rule parameters: subset comparison (see the policy note at the top).
    foreach ($type in $expectedTypes) {
        if ($actualTypes -notcontains $type) { continue }
        $expParams = $expectedMap[$type]
        if ($null -eq $expParams) { continue }
        $actParams = $actualMap[$type]
        foreach ($prop in $expParams.PSObject.Properties) {
            $e = ConvertTo-FactValue -Value $prop.Value
            $actProp = $null
            if ($null -ne $actParams) {
                $actProp = $actParams.PSObject.Properties[$prop.Name]
            }
            if ($null -eq $actProp) {
                $diffs += "rules.$type.$($prop.Name): expected=$e actual=(absent)"
                continue
            }
            $a = ConvertTo-FactValue -Value $actProp.Value
            if ($e -ne $a) {
                $diffs += "rules.$type.$($prop.Name): expected=$e actual=$a"
            }
        }
    }

    $status = 'match'
    if ($diffs.Count -gt 0) { $status = 'drift' }
    return [PSCustomObject]@{ Status = $status; Differences = $diffs }
}

function Format-RulesetReport {
    # Render the comparison result as report lines. The machine-readable
    # "STATUS: <status>" line is always the last line so callers (skill /
    # scheduled task) can parse it without depending on exit codes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Result
    )

    $lines = @()
    $lines += "=== branch protection: $Name ($Repo) ==="
    switch ($Result.Status) {
        'match' {
            $lines += "[OK] applied -- the ruleset matches the kit template."
        }
        'missing' {
            $lines += "[NG] not applied -- no ruleset named '$Name' exists on this repository."
            $lines += "     Apply it with: scripts/apply-branch-protection.ps1 -Repo $Repo"
        }
        'drift' {
            $lines += "[WARN] drift -- the ruleset exists but differs from the kit template:"
            foreach ($d in $Result.Differences) { $lines += "  - $d" }
            $lines += "     Reconcile with: scripts/apply-branch-protection.ps1 -Repo $Repo"
        }
    }
    $lines += "STATUS: $($Result.Status)"
    return $lines
}

function Get-BranchProtectionExitCode {
    # 0 = match, 1 = drift, 2 = missing. Errors exit 3 from the entry scripts.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Status)

    switch ($Status) {
        'match'   { return 0 }
        'drift'   { return 1 }
        'missing' { return 2 }
        default   { return 3 }
    }
}

function Copy-BranchProtectionTask {
    # Deploy templates/scheduled-tasks/check-branch-protection/*.md into
    # <TargetRoot>/scheduled-tasks/check-branch-protection/. Called by
    # apply-claude-kit.ps1 (Global mode, opt-in). Returns the deployed paths.
    # Project mode is a silent no-op: scheduled tasks are per-user, not per-repo.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplatesRoot,
        [Parameter(Mandatory)][string]$TargetRoot,
        [string]$Mode = "Global",
        [switch]$Enabled,
        [switch]$IsDryRun
    )

    if ($Mode -ne "Global") { return @() }
    if (-not $Enabled) {
        Write-Host "[skip] branch-protection scheduled-task not deployed (pass -EnableBranchProtectionSchedule to opt in)."
        return @()
    }

    $taskName = "check-branch-protection"
    $sourceDir = Join-Path (Join-Path $TemplatesRoot "scheduled-tasks") $taskName
    if (-not (Test-Path -LiteralPath $sourceDir)) { return @() }

    $deployed = @()
    foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -Filter "*.md" -File)) {
        $destDir = Join-Path (Join-Path $TargetRoot "scheduled-tasks") $taskName
        $dest = Join-Path $destDir $file.Name
        if ($IsDryRun) {
            Write-Host "[dry-run] $($file.FullName) -> $dest"
        } else {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
            Write-Host "[apply] $($file.FullName) -> $dest"
        }
        $deployed += $dest
    }
    return $deployed
}

# When dot-sourced (the kit's convention) the functions are already visible in
# the caller scope, so Export-ModuleMember must be skipped: it errors outside a
# module and these scripts run with $ErrorActionPreference = 'Stop'.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function `
        Get-RepoFromGitRemote, Read-RulesetTemplate, New-RulesetRequestBody, `
        Invoke-GhApi, Get-RepoRuleset, ConvertTo-FactValue, Get-RuleParameterMap, `
        Compare-RulesetState, Format-RulesetReport, Get-BranchProtectionExitCode, `
        Copy-BranchProtectionTask
}
