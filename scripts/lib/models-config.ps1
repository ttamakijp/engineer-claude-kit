#requires -Version 5.1
# models-config.ps1
# Shared helper: load config/models.yaml and resolve {{role:<name>}} placeholders.
# Provides: Read-ConfigYaml, Resolve-ModelId, Invoke-TemplateSubstitution.
#
# Extracted from apply-claude-kit.ps1 (see ADR-0001 section I, ADR-0004 section B/D)
# to keep that script under the file-granularity hard limit (500 lines) and to
# give config/model resolution a single-responsibility home. Depends on
# Read-Utf8NoBom from encoding-helper.ps1, which the caller dot-sources first.
#
# ASCII only (no Japanese in code, comments, or strings).

# --- minimal YAML reader for our config schema ---

function Read-ConfigYaml {
    param([string]$Path)

    # Returns a hashtable. Supports:
    #   key: value
    #   key:
    #     subkey: value
    #     subkey:
    #       nestedkey: value
    #   key: [a, b, c]
    # Indentation is 2 spaces. Comments start with #. No anchors, no multi-line scalars.

    $content = Read-Utf8NoBom -Path $Path
    $lines = $content -split "`r?`n"
    $root = @{}
    $stack = @(@{ Indent = -1; Map = $root })

    foreach ($rawLine in $lines) {
        if ($rawLine -match '^\s*#') { continue }
        if ($rawLine -match '^\s*$') { continue }

        # Remove trailing comments (very simple - does not handle # inside quotes)
        $line = $rawLine -replace '\s+#.*$', ''

        # Indent count (spaces only)
        $indent = 0
        while ($indent -lt $line.Length -and $line[$indent] -eq ' ') { $indent++ }

        # Pop stack until parent indent < current indent
        while ($stack.Count -gt 1 -and $stack[-1].Indent -ge $indent) {
            $stack = $stack[0..($stack.Count - 2)]
        }
        $current = $stack[-1].Map

        $body = $line.Substring($indent)
        if ($body -match '^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()

            if ($val -eq '') {
                $child = @{}
                $current[$key] = $child
                $stack += @{ Indent = $indent; Map = $child }
            } elseif ($val -match '^\[(.*)\]$') {
                $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") }
                $current[$key] = $items
            } else {
                $clean = $val.Trim('"').Trim("'")
                $current[$key] = $clean
            }
        } elseif ($body -match '^-\s+(.*)$') {
            # List item under a key whose value started as block.
            # Phase 2.2 Q only consumes models.yaml (maps only), so list items are
            # stored as plain strings under a "_list" key for any future caller.
            if (-not $current.ContainsKey('_list')) { $current['_list'] = @() }
            $current['_list'] += $Matches[1].Trim()
        }
    }

    return $root
}

# --- model role resolution ---

function Resolve-ModelId {
    param(
        [hashtable]$ModelsConfig,
        [string]$Role
    )

    $models = $ModelsConfig['models']
    if ($null -eq $models) {
        throw "config/models.yaml: missing 'models' key"
    }

    if ($models.ContainsKey($Role)) {
        $id = $models[$Role]['id']
        if (-not $id) {
            throw "config/models.yaml: model '$Role' has no 'id' field"
        }
        return $id
    }

    # Lookup via roles.<role>.role-of
    $roles = $ModelsConfig['roles']
    if ($null -ne $roles -and $roles.ContainsKey($Role)) {
        $roleOf = $roles[$Role]['role-of']
        if ($roleOf) {
            return (Resolve-ModelId -ModelsConfig $ModelsConfig -Role $roleOf)
        }
    }

    throw "config/models.yaml: cannot resolve model role '$Role'"
}

# --- template substitution ---

function Invoke-TemplateSubstitution {
    param(
        [string]$TemplateContent,
        [hashtable]$ModelsConfig
    )

    $result = $TemplateContent

    # Find all {{role:<name>}} placeholders. {{user.*}} placeholders are reserved
    # for a future phase and intentionally left untouched here.
    $pattern = '\{\{role:([a-z][a-z0-9-]*)\}\}'
    $placeholderMatches = [System.Text.RegularExpressions.Regex]::Matches($result, $pattern)
    foreach ($m in $placeholderMatches) {
        $role = $m.Groups[1].Value
        $id = Resolve-ModelId -ModelsConfig $ModelsConfig -Role $role
        $result = $result -replace ('\{\{role:' + [regex]::Escape($role) + '\}\}'), $id
    }

    return $result
}

# Expose the functions when this file is imported as a module. The kit dot-sources
# it (see apply-claude-kit.ps1), in which case the functions are already visible in
# the caller scope and Export-ModuleMember must be skipped: it errors outside a
# module, and the caller runs with $ErrorActionPreference=Stop.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Read-ConfigYaml, Resolve-ModelId, Invoke-TemplateSubstitution
}
