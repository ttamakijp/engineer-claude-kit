#requires -Version 5.1
# setup-wizard.ps1
# Interactive, opt-in bootstrap for ~/.claude/settings.json.
#
# ADR-0007 keeps the kit hands-off: it never writes settings.json without the
# user's explicit consent. This wizard is the sanctioned exception (ADR-0010):
# it ASKS before every change, only ADDS missing keys via deep merge (existing
# keys are never overwritten), backs up before writing, and skips itself in any
# non-interactive context (CI / -NonInteractive / no UserInteractive console).
#
# Provides: Invoke-SettingsSetupWizard (plus the helpers it composes).
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.
# PS 5.1 compatible: no -AsHashtable, no PS 6+ syntax.

function Test-IsInteractive {
    # Non-interactive when running under CI, when caller forces it, or when the
    # process has no interactive console (service / redirected host).
    if ($env:CI) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    return $true
}

function ConvertTo-HashtableRecursive {
    # PSCustomObject -> Hashtable, recursively. ConvertFrom-Json on PS 5.1 has no
    # -AsHashtable, so we normalize the object graph ourselves. PS 7 works too.
    param($Object)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Object.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-HashtableRecursive $p.Value
        }
        return $h
    }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        return @($Object | ForEach-Object { ConvertTo-HashtableRecursive $_ })
    }
    return $Object
}

function Read-CurrentSettings {
    # Load settings.json as a (possibly nested) hashtable. Missing / empty /
    # unparseable file yields an empty hashtable so the caller can merge freely.
    param([string]$Path = "$env:USERPROFILE\.claude\settings.json")

    if (-not (Test-Path $Path)) { return @{} }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    try {
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "settings.json is not valid JSON; treating as empty. ($_)"
        return @{}
    }
    $h = ConvertTo-HashtableRecursive $obj
    if ($h -is [hashtable]) { return $h }
    return @{}
}

function Merge-Hashtable {
    # Deep merge: return a copy of $Base with the *missing* keys from $Overlay
    # added. Existing keys are never overwritten; nested hashtables merge
    # recursively. This is the only mutation semantic the wizard is allowed.
    param([hashtable]$Base, [hashtable]$Overlay)

    $result = $Base.Clone()
    foreach ($key in $Overlay.Keys) {
        if (-not $result.ContainsKey($key)) {
            $result[$key] = $Overlay[$key]
        } elseif ($result[$key] -is [hashtable] -and $Overlay[$key] -is [hashtable]) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Overlay $Overlay[$key]
        }
        # Existing scalar (or type-mismatched) values are left untouched.
    }
    return $result
}

function Save-SettingsWithBackup {
    # Write settings.json as UTF-8 (no BOM) via the shared encoding helper,
    # creating a timestamped backup of any pre-existing file first.
    param(
        [hashtable]$Settings,
        [string]$Path = "$env:USERPROFILE\.claude\settings.json"
    )

    . (Join-Path (Join-Path $PSScriptRoot "lib") "encoding-helper.ps1")

    if (Test-Path $Path) {
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $Path -Destination "$Path.bak-$ts" -Force
    } else {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }

    $json = $Settings | ConvertTo-Json -Depth 100
    Write-Utf8NoBom -Path $Path -Content $json
}

function Get-DefaultHaikuModelId {
    # Bedrock and Anthropic API use different model-id formats. Pick by backend.
    param([ValidateSet('bedrock', 'anthropic')][string]$Backend)
    if ($Backend -eq 'bedrock') {
        return 'us.anthropic.claude-haiku-4-5-20251001-v1:0'
    }
    return 'claude-haiku-4-5-20251001'
}

function Invoke-SettingsSetupWizard {
    # Interactive settings.json bootstrap. Default answer is Y (Enter adds the
    # item); only an explicit N declines. Skips entirely when non-interactive.
    param(
        [switch]$NonInteractive,
        [string]$Path = "$env:USERPROFILE\.claude\settings.json"
    )

    if ($NonInteractive -or -not (Test-IsInteractive)) {
        Write-Host "[skip] Non-interactive mode, settings wizard skipped."
        return
    }

    Write-Host ""
    Write-Host "=== Settings setup wizard ==="
    Write-Host "Adds missing settings only; existing values are never overwritten (ADR-0010)."
    Write-Host ""

    $settings = Read-CurrentSettings -Path $Path
    $modified = $false

    # --- 1. statusLine ---
    if (-not $settings.ContainsKey('statusLine')) {
        Write-Host "[?] statusLine setting not found."
        Write-Host "    Add a 'current model + color-coded context usage' statusline?"
        Write-Host "    (green < 75%, yellow 75-90%, red >= 90%; see ADR-0012)"
        $ans = Read-Host "    [Y]es / [n]o (default: Y)"
        if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^[Yy]') {
            $settings['statusLine'] = @{
                type    = 'command'
                command = 'powershell -NoProfile -Command "$input | ConvertFrom-Json | ForEach-Object { $p=[Math]::Floor($_.context_window.used_percentage); $c=if($p -ge 90){''31''}elseif($p -ge 75){''33''}else{''32''}; Write-Host ([char]27 + ''['' + $c + ''m['' + $_.model.display_name + ''] '' + $p + ''% context'' + [char]27 + ''[0m'') }"'
            }
            $modified = $true
            Write-Host "[OK] statusLine added"
        } else {
            Write-Host "[skip] statusLine declined"
        }
    } else {
        Write-Host "[ok] statusLine already configured"
    }

    # --- 2. ANTHROPIC_SMALL_FAST_MODEL ---
    $hasSmallFast = $settings.ContainsKey('env') `
        -and ($settings['env'] -is [hashtable]) `
        -and $settings['env'].ContainsKey('ANTHROPIC_SMALL_FAST_MODEL')

    if (-not $hasSmallFast) {
        Write-Host ""
        Write-Host "[?] ANTHROPIC_SMALL_FAST_MODEL not configured."
        Write-Host "    Adding it enables Haiku delegation for lightweight tasks (ADR-0004)."

        $bedrock = ($env:CLAUDE_CODE_USE_BEDROCK -eq '1')
        if ($bedrock) {
            Write-Host "    Detected Bedrock (CLAUDE_CODE_USE_BEDROCK=1)."
            $ans = Read-Host "    Add Bedrock Haiku id? [Y]es / [n]o (default: Y)"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = 'Y' }
        } else {
            Write-Host "    Choose your backend:"
            Write-Host "      [1] Bedrock"
            Write-Host "      [2] Anthropic API direct"
            Write-Host "      [s] Skip"
            $ans = Read-Host "    Selection [1/2/s] (default: 1)"
            if ([string]::IsNullOrWhiteSpace($ans)) { $ans = '1' }
        }

        $haiku = $null
        if ($bedrock) {
            if ($ans -match '^[Yy]') { $haiku = Get-DefaultHaikuModelId -Backend 'bedrock' }
        } else {
            if ($ans -match '^1') { $haiku = Get-DefaultHaikuModelId -Backend 'bedrock' }
            elseif ($ans -match '^2') { $haiku = Get-DefaultHaikuModelId -Backend 'anthropic' }
        }

        if ($haiku) {
            if (-not ($settings.ContainsKey('env') -and ($settings['env'] -is [hashtable]))) {
                $settings['env'] = @{}
            }
            $settings['env']['ANTHROPIC_SMALL_FAST_MODEL'] = $haiku
            $modified = $true
            Write-Host "[OK] ANTHROPIC_SMALL_FAST_MODEL = $haiku"
        } else {
            Write-Host "[skip] ANTHROPIC_SMALL_FAST_MODEL declined"
        }
    } else {
        Write-Host "[ok] ANTHROPIC_SMALL_FAST_MODEL already configured"
    }

    # --- save ---
    if ($modified) {
        Save-SettingsWithBackup -Settings $settings -Path $Path
        Write-Host ""
        Write-Host "[OK] settings.json updated. Backup saved as .bak-<timestamp> (if a prior file existed)."
    } else {
        Write-Host ""
        Write-Host "[OK] No changes needed."
    }
    Write-Host ""
}

# Expose functions when imported as a module. When dot-sourced (the kit's usual
# path), the functions are already visible and Export-ModuleMember must be
# skipped: it errors outside a module under $ErrorActionPreference=Stop.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function `
        Test-IsInteractive, ConvertTo-HashtableRecursive, Read-CurrentSettings, `
        Merge-Hashtable, Save-SettingsWithBackup, Get-DefaultHaikuModelId, `
        Invoke-SettingsSetupWizard
}
