# config/rules.ps1
# Rule registry: PowerShell hashtable defining all deployable rules.
# Each rule entry maps to source_path + deployment metadata.
# PS 5.1 compatible. UTF-8 no BOM.

$RuleRegistry = @{
    'version-management' = @{
        id              = 'version-management'
        title           = 'Version management'
        description     = 'App version system + in-app display + CI auto-increment'
        applies_to      = @('android', 'ios', 'firmware', 'web')
        priority        = 'high'
        source_path     = 'source/rules/common/version-management.md'
        target_path     = '.claude/rules/version-management.md'
        override_allowed = $true
        keywords        = @('versioning', 'semver', 'buildnumber', 'release')
    }
    'commit-convention' = @{
        id              = 'commit-convention'
        title           = 'Commit and PR convention'
        description     = 'Conventional Commits + squash merge + PR per phase'
        applies_to      = @('*')
        priority        = 'high'
        source_path     = 'source/rules/common/commit-convention.md'
        target_path     = '.claude/rules/commit-convention.md'
        override_allowed = $true
        keywords        = @('git', 'commit', 'workflow')
    }
    'file-granularity' = @{
        id              = 'file-granularity'
        title           = 'File granularity'
        description     = '1 file <= 300 lines, strict max 500 lines'
        applies_to      = @('*')
        priority        = 'medium'
        source_path     = 'source/rules/common/file-granularity.md'
        target_path     = '.claude/rules/file-granularity.md'
        override_allowed = $true
        keywords        = @('architecture', 'maintainability')
    }
    'security-mobile' = @{
        id              = 'security-mobile'
        title           = 'Mobile security'
        description     = 'OWASP Mobile Top 10 + API key management + data protection'
        applies_to      = @('android', 'ios')
        priority        = 'critical'
        source_path     = 'source/rules/common/security-mobile.md'
        target_path     = '.claude/rules/security-mobile.md'
        override_allowed = $true
        keywords        = @('security', 'owasp', 'encryption')
    }
    'bilingual-notation' = @{
        id              = 'bilingual-notation'
        title           = 'Bilingual notation'
        description     = 'Japanese translation for English terms on first use'
        applies_to      = @('*')
        priority        = 'low'
        source_path     = 'source/rules/common/bilingual-notation.md'
        target_path     = '.claude/rules/bilingual-notation.md'
        override_allowed = $true
        keywords        = @('documentation', 'style')
    }
}

Write-Output $RuleRegistry
