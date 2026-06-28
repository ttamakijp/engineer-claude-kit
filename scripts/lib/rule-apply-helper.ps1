# scripts/lib/rule-apply-helper.ps1
# Rule application helper: modular entry point for rule injection.
# PS 5.1 compatible. Depends on encoding-helper.ps1.

function Invoke-RuleApplyHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$KitRoot,

        [Parameter(Mandatory=$true)]
        [string]$TargetRoot,

        [switch]$DryRun
    )

    # Load rule registry
    $rulesConfigPath = Join-Path $KitRoot "config" "rules.ps1"
    if (-not (Test-Path $rulesConfigPath)) {
        Write-Warning "[rule-apply-helper] Rule registry not found: $rulesConfigPath"
        return @()
    }

    # Dot-source rules registry
    $RuleRegistry = @{}
    try {
        & ([scriptblock]::Create((Get-Content -LiteralPath $rulesConfigPath -Raw)))
    } catch {
        Write-Warning "[rule-apply-helper] Failed to load rule registry: ${_}"
        return @()
    }

    # Inject rules
    $applied = @()
    foreach ($ruleId in $RuleRegistry.Keys) {
        $rule = $RuleRegistry[$ruleId]
        $sourcePath = Join-Path $KitRoot $rule.source_path
        $targetPath = Join-Path $TargetRoot $rule.target_path

        if (-not (Test-Path $sourcePath)) {
            Write-Verbose "[rule-apply-helper] Source not found (skipping): $sourcePath"
            continue
        }

        # Check override
        if ((Test-Path $targetPath) -and -not $rule.override_allowed) {
            Write-Verbose "[rule-apply-helper] Target exists, override=false (skipping): $targetPath"
            continue
        }

        # Create directory
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            if ($DryRun) {
                Write-Host "[dry-run] mkdir $targetDir"
            } else {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        }

        # Copy with UTF-8 no BOM
        if ($DryRun) {
            Write-Host "[dry-run] cp $sourcePath -> $targetPath (rule: $ruleId)"
        } else {
            try {
                $content = Read-Utf8NoBom -Path $sourcePath
                Write-Utf8NoBom -Path $targetPath -Content $content
                Write-Host "[apply] $sourcePath -> $targetPath (rule: $ruleId)"
            } catch {
                Write-Warning "[rule-apply-helper] Failed to copy ${ruleId}: ${_}"
                continue
            }
        }

        $applied += $targetPath
    }

    return $applied
}

Write-Verbose "rule-apply-helper.ps1 loaded"
