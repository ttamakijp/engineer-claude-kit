# settings-migration.ps1
# Automatically migrate settings.json hooks from deprecated event names to current schema.
# Called by apply-claude-kit.ps1 during Global mode setup.
#
# Migration targets:
#   - 'on-exit' (deprecated) -> 'SessionEnd' (valid)
#   - 'after-command' (deprecated) -> 'PostToolBatch' (valid)
#   - Hook objects -> Hook arrays (schema requirement)

function Invoke-SettingsMigration {
    param(
        [string]$SettingsPath,
        [switch]$IsDryRun
    )

    if (-not (Test-Path $SettingsPath)) {
        Write-Host "[settings-migration] $SettingsPath not found, skipping."
        return
    }

    try {
        $content = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
        $settings = $content | ConvertFrom-Json
    } catch {
        Write-Host "[settings-migration] Failed to parse $SettingsPath : $_"
        return
    }

    $migrated = $false

    # Ensure hooks key exists
    if ($null -eq $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
    }

    # Migration 1: 'on-exit' -> 'SessionEnd'
    if ($settings.hooks | Get-Member -Name "on-exit") {
        Write-Host "[settings-migration] Found deprecated 'on-exit' hook, converting to 'SessionEnd'..."
        $oldHook = $settings.hooks."on-exit"

        # Convert object to array
        if ($oldHook -is [hashtable] -or $oldHook -is [PSCustomObject]) {
            $newHook = @($oldHook)
        } elseif ($oldHook -is [array]) {
            $newHook = $oldHook
        } else {
            $newHook = @($oldHook)
        }

        # Remove old key and add new one
        $settings.hooks.PSObject.Properties.Remove("on-exit")
        $settings.hooks | Add-Member -NotePropertyName "SessionEnd" -NotePropertyValue $newHook

        Write-Host "[settings-migration]   ✓ Migrated 'on-exit' -> 'SessionEnd'"
        $migrated = $true
    }

    # Migration 2: 'after-command' -> 'PostToolBatch'
    if ($settings.hooks | Get-Member -Name "after-command") {
        Write-Host "[settings-migration] Found deprecated 'after-command' hook, converting to 'PostToolBatch'..."
        $oldHook = $settings.hooks."after-command"

        # Convert object to array
        if ($oldHook -is [hashtable] -or $oldHook -is [PSCustomObject]) {
            $newHook = @($oldHook)
        } elseif ($oldHook -is [array]) {
            $newHook = $oldHook
        } else {
            $newHook = @($oldHook)
        }

        # Remove old key and add new one
        $settings.hooks.PSObject.Properties.Remove("after-command")
        $settings.hooks | Add-Member -NotePropertyName "PostToolBatch" -NotePropertyValue $newHook

        Write-Host "[settings-migration]   ✓ Migrated 'after-command' -> 'PostToolBatch'"
        $migrated = $true
    }

    # Migration 3: Convert remaining hook objects to arrays (schema requirement)
    $hookKeys = $settings.hooks.PSObject.Properties.Name
    foreach ($key in $hookKeys) {
        $hookValue = $settings.hooks.$key
        if ($hookValue -isnot [array]) {
            if ($hookValue -is [hashtable] -or $hookValue -is [PSCustomObject]) {
                $settings.hooks.$key = @($hookValue)
                Write-Host "[settings-migration] Converted '$key' hook to array format"
                $migrated = $true
            }
        }
    }

    if (-not $migrated) {
        Write-Host "[settings-migration] No migrations needed."
        return
    }

    if ($IsDryRun) {
        Write-Host "[settings-migration] [dry-run] Would write migrated settings to $SettingsPath"
        Write-Host "[settings-migration] [dry-run] Migrated content:"
        Write-Host ($settings | ConvertTo-Json -Depth 10)
        return
    }

    # Write back the migrated settings (preserve UTF-8 BOM/no-BOM style)
    try {
        $jsonContent = $settings | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $SettingsPath -Value $jsonContent -Encoding UTF8
        Write-Host "[settings-migration] ✓ Successfully migrated $SettingsPath"
    } catch {
        Write-Host "[settings-migration] Failed to write $SettingsPath : $_"
    }
}
