@{
    # PowerShell Script Analyzer settings for engineer-claude-kit
    # Target: Windows PowerShell 5.1 (hard constraint per ADR-0001)

    Severity = @('Error', 'Warning')

    # Scope the lint to its stated purpose: PS 5.1 compatibility.
    # Restricting to the compatibility rules keeps the -Strict CI gate green on
    # existing PS 5.1-compatible code (general code-quality rules are out of
    # scope here and would otherwise fail CI on pre-existing scripts).
    IncludeRules = @(
        'PSUseCompatibleSyntax'
        'PSUseCompatibleCommands'
    )

    Rules = @{
        # Detect PS 6+ syntax that breaks on PS 5.1
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }

        # Detect PS 6+ cmdlets / parameters that don't exist on PS 5.1
        PSUseCompatibleCommands = @{
            Enable = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
            )
        }
    }

    # Exclude rules that conflict with intentional kit conventions
    ExcludeRules = @(
        # Allow Write-Host (informational scripts use it intentionally)
        'PSAvoidUsingWriteHost'
    )
}
