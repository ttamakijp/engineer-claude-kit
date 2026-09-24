#!/usr/bin/env bash
# branch-protection.sh
# Shared helper for the GitHub branch-protection ruleset feature (macOS / Linux).
# POSIX-ish bash 3.2+ (macOS ships bash 3.2), requires gh and jq.
#
# This is the bash counterpart of scripts/lib/branch-protection.ps1 and applies
# the same comparison policy:
#   - rule TYPES are compared exactly in both directions
#   - rule PARAMETERS are compared as a subset: parameters GitHub adds on its
#     own are pruned before the diff, so they never read as drift
#
# Sourced by check-branch-protection.sh and apply-branch-protection.sh.
# ASCII only. See ADR-0003 section C.

# Globals set by the functions below.
BP_STATUS=""       # match | drift | missing
BP_DIFF=""         # unified diff (expected -> actual) when BP_STATUS=drift
BP_RULESET_ID=""   # id of the matched ruleset (empty when missing)

# jq program: canonicalize a ruleset for comparison. $exp is the expected
# (template) ruleset and drives the parameter pruning described above.
BP_CANON_FILTER='
def prune($exp):
  {
    enforcement: .enforcement,
    target: .target,
    conditions: {
      ref_name: {
        include: ((.conditions.ref_name.include // []) | sort),
        exclude: ((.conditions.ref_name.exclude // []) | sort)
      }
    },
    rules: ((.rules // []) | map(
        . as $r
        | ((($exp.rules // []) | map(select(.type == $r.type)) | first | .parameters) // {}) as $ep
        | { type: $r.type,
            parameters: (($r.parameters // {}) | with_entries(select(.key as $k | $ep | has($k)))) }
      ) | sort_by(.type)),
    bypass_actors: (.bypass_actors // [])
  };
prune($exp) | walk(if type == "array" then sort else . end)
'

bp_require_tools() {
    local missing=0
    if ! command -v gh >/dev/null 2>&1; then
        echo "[error] GitHub CLI (gh) not found. Install it and run 'gh auth login'." >&2
        missing=1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "[error] jq not found. Install it (brew install jq / apt-get install jq)." >&2
        missing=1
    fi
    return "$missing"
}

bp_repo_from_git_remote() {
    # Echo OWNER/REPO derived from the git remote of $1 (default: cwd).
    # Echoes nothing when the remote is missing or is not a GitHub URL.
    local path="${1:-.}" remote="${2:-origin}" url
    url="$(git -C "$path" remote get-url "$remote" 2>/dev/null || true)"
    [ -n "$url" ] || return 0
    url="${url%.git}"
    url="${url%/}"
    case "$url" in
        *github.com[:/]*)
            # Keep the final two path segments: OWNER/REPO.
            printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#^/##'
            ;;
        *) return 0 ;;
    esac
}

bp_fetch_ruleset() {
    # Echo the full detail JSON of the ruleset named $2 on repo $1.
    # Returns 0 when found, 1 when no such ruleset exists, 3 on API failure.
    # Sets BP_RULESET_ID on success.
    local repo="$1" name="$2" list id detail
    BP_RULESET_ID=""

    if ! list="$(gh api "repos/$repo/rulesets" 2>&1)"; then
        echo "[error] gh api repos/$repo/rulesets failed:" >&2
        echo "$list" >&2
        return 3
    fi

    id="$(printf '%s' "$list" | jq -r --arg n "$name" \
        'map(select(.name == $n)) | first | .id // empty' 2>/dev/null || true)"
    [ -n "$id" ] || return 1

    if ! detail="$(gh api "repos/$repo/rulesets/$id" 2>&1)"; then
        echo "[error] gh api repos/$repo/rulesets/$id failed:" >&2
        echo "$detail" >&2
        return 3
    fi
    BP_RULESET_ID="$id"
    printf '%s' "$detail"
}

bp_canon() {
    # bp_canon <expected-json> <input-json>
    jq -S --argjson exp "$1" "$BP_CANON_FILTER" <<<"$2"
}

bp_compare() {
    # bp_compare <expected-json> <actual-json|"">  -> sets BP_STATUS / BP_DIFF
    local expected="$1" actual="$2" e a
    BP_DIFF=""
    if [ -z "$actual" ] || [ "$actual" = "null" ]; then
        BP_STATUS="missing"
        return 0
    fi
    e="$(bp_canon "$expected" "$expected")"
    a="$(bp_canon "$expected" "$actual")"
    if [ "$e" = "$a" ]; then
        BP_STATUS="match"
    else
        BP_STATUS="drift"
        BP_DIFF="$(diff -u <(printf '%s\n' "$e") <(printf '%s\n' "$a") \
            | tail -n +3 || true)"
    fi
}

bp_request_body() {
    # Strip response-only fields before POST / PUT.
    jq -c 'del(.source_type, .source, .id, .node_id, .created_at, .updated_at, ._links, .current_user_can_bypass)' <<<"$1"
}

bp_report() {
    # bp_report <repo> <name>. Prints the report; the last line is always
    # "STATUS: <state>" so callers can parse it without exit codes.
    local repo="$1" name="$2"
    echo "=== branch protection: $name ($repo) ==="
    case "$BP_STATUS" in
        match)
            echo "[OK] applied -- the ruleset matches the kit template."
            ;;
        missing)
            echo "[NG] not applied -- no ruleset named '$name' exists on this repository."
            echo "     Apply it with: scripts/apply-branch-protection.sh --repo $repo"
            ;;
        drift)
            echo "[WARN] drift -- the ruleset exists but differs from the kit template:"
            echo "       ('-' = kit template, '+' = current repository state)"
            printf '%s\n' "$BP_DIFF" | sed 's/^/  /'
            echo "     Reconcile with: scripts/apply-branch-protection.sh --repo $repo"
            ;;
    esac
    echo "STATUS: $BP_STATUS"
}

bp_exit_code() {
    # 0 = match, 1 = drift, 2 = missing, 3 = error.
    case "$BP_STATUS" in
        match)   echo 0 ;;
        drift)   echo 1 ;;
        missing) echo 2 ;;
        *)       echo 3 ;;
    esac
}
