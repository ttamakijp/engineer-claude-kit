#requires -Version 5.1
# plain-language.ps1
# Shared helper: render a plain-language (Japanese) blockquote hint for a usage
# finding category, to be appended after the technical metric in the insights
# report. Provides: Get-PlainLanguageHint.
#
# Why the hint text lives in an external JSON, not inline here (see ADR-0014):
#   - This kit enforces ASCII-only PowerShell sources (no Japanese literals in
#     .ps1). PS 5.1 also parses BOM-less .ps1 files with the system ANSI codepage
#     (CP932 on Japanese Windows), so inline Japanese would mojibake at parse time.
#   - Routing the Japanese through plain-language-hints.json + Read-Utf8NoBom (a
#     forced, codepage-independent UTF-8 decode) keeps this script ASCII-only and
#     renders correctly on every PowerShell version. Read-Utf8NoBom is supplied by
#     encoding-helper.ps1, which usage-insights.ps1 dot-sources before this file.
#
# ASCII only (no Japanese in code, comments, or strings). See ADR-0014.

function Get-PlainLanguageHint {
    # Return the plain-language hint for $Category as a Markdown blockquote block:
    # a leading blank line, then one "> <sentence>" line per mapped sentence. An
    # unknown category, a missing data file, or a malformed file yields '' so the
    # caller appends nothing (the technical metric is always preserved separately).
    param(
        [Parameter(Mandatory)][string]$Category,
        [string]$HintsFile
    )
    if (-not $HintsFile) {
        $HintsFile = Join-Path $PSScriptRoot 'plain-language-hints.json'
    }
    if (-not (Test-Path -LiteralPath $HintsFile)) { return '' }

    $map = $null
    try { $map = (Read-Utf8NoBom -Path $HintsFile) | ConvertFrom-Json } catch { return '' }
    if (-not $map) { return '' }

    $sentences = $map.$Category
    if (-not $sentences) { return '' }

    $out = @('')
    foreach ($s in $sentences) { $out += "> $s" }
    return ($out -join "`n")
}
