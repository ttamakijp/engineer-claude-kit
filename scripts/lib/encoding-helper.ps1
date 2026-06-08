#requires -Version 5.1
# encoding-helper.ps1
# Shared helper: environment-aware UTF-8 (no BOM) file I/O.
# Provides: Write-Utf8NoBom, Read-Utf8NoBom.
#
# Why this exists (see ADR-0003 section C):
#   - PS 5.1 Get-Content / Set-Content default to the system ANSI codepage
#     (CP932 on Japanese Windows), NOT UTF-8. Reading a UTF-8 source with the
#     default codepage corrupts every multibyte character, and writing it back
#     as UTF-8 produces double-encoded mojibake.
#   - PS 5.1 "-Encoding UTF8" writes UTF-8 WITH a BOM (EF BB BF), which breaks
#     CLAUDE.md frontmatter parsing and trips git binary-marker warnings.
#   - Routing all kit reads/writes through these two helpers guarantees UTF-8
#     without a BOM on every PowerShell version.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0003 section C.

function Write-Utf8NoBom {
    # Write text as UTF-8 without a BOM, regardless of PowerShell version.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Mandatory, Position = 1)][string]$Content
    )

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PS 6+ supports the utf8NoBOM encoding name directly.
        $Content | Set-Content -LiteralPath $Path -Encoding utf8NoBOM -NoNewline
    } else {
        # PS 5.1: "-Encoding UTF8" emits a BOM, so go through the .NET API with
        # UTF8Encoding($false) to suppress it.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
    }
}

function Read-Utf8NoBom {
    # Read a file as UTF-8 and strip a leading BOM (U+FEFF) if present.
    # Independent of the host's default codepage, so it never mojibakes UTF-8
    # source under Windows PowerShell 5.1.
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Path)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $content = [System.IO.File]::ReadAllText($Path, $utf8)
    return $content.TrimStart([char]0xFEFF)
}

# Expose the functions when this file is imported as a module. The kit dot-sources
# it (see privilege-check.ps1 / apply-claude-kit.ps1), in which case the functions
# are already visible in the caller scope and Export-ModuleMember must be skipped:
# it errors outside a module, and the caller runs with $ErrorActionPreference=Stop.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Write-Utf8NoBom, Read-Utf8NoBom
}
