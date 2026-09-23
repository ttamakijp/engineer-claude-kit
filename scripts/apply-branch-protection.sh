#!/usr/bin/env bash
# apply-branch-protection.sh
# Create or reconcile the kit's protect-main ruleset on a GitHub repository.
#
# not applied -> POST repos/OWNER/REPO/rulesets  (creates the ruleset)
# drift       -> show the diff, ask Y/N, then PUT repos/.../rulesets/<id>
# match       -> nothing to do
#
# Usage:
#   scripts/apply-branch-protection.sh [--repo OWNER/REPO] [--name protect-main]
#                                      [--template PATH] [--path DIR]
#                                      [--dry-run] [--force]
#   --dry-run reports what would happen and writes nothing.
#   --force answers the drift prompt with yes (non-interactive automation).
#
# Exit codes: 0 = applied / already correct, 1 = declined or drift left as-is,
#             3 = error.
# ASCII only. See ADR-0003 section C.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/branch-protection.sh
. "$SCRIPT_DIR/lib/branch-protection.sh"

REPO=""
NAME="protect-main"
TEMPLATE="$KIT_ROOT/templates/branch-protection/protect-main.json"
REPO_PATH="."
DRY_RUN=0
FORCE=0

usage() {
    sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo|-Repo)         REPO="${2:-}"; shift 2 ;;
        --name|-Name)         NAME="${2:-}"; shift 2 ;;
        --template|-Template) TEMPLATE="${2:-}"; shift 2 ;;
        --path|-Path)         REPO_PATH="${2:-}"; shift 2 ;;
        --dry-run|-DryRun)    DRY_RUN=1; shift ;;
        --force|-Force)       FORCE=1; shift ;;
        -h|--help)            usage; exit 0 ;;
        *) echo "[error] unknown argument: $1" >&2; usage >&2; exit 3 ;;
    esac
done

bp_require_tools || exit 3

if [ -z "$REPO" ]; then
    REPO="$(bp_repo_from_git_remote "$REPO_PATH")"
    if [ -z "$REPO" ]; then
        echo "[error] --repo was not given and no GitHub remote could be resolved from: $REPO_PATH" >&2
        exit 3
    fi
    echo "[info] repo inferred from git remote: $REPO"
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "[error] ruleset template not found: $TEMPLATE" >&2
    exit 3
fi
EXPECTED="$(cat "$TEMPLATE")"

set +e
ACTUAL="$(bp_fetch_ruleset "$REPO" "$NAME")"
FETCH_RC=$?
set -e
if [ "$FETCH_RC" -eq 3 ]; then
    exit 3
elif [ "$FETCH_RC" -eq 1 ]; then
    ACTUAL=""
fi

bp_compare "$EXPECTED" "$ACTUAL"
bp_report "$REPO" "$NAME"

# Written as an if block, not `[ ... ] && exit 0`: under `set -e` an AND-OR list
# whose test fails leaves a non-zero status behind, which is easy to trip over.
if [ "$BP_STATUS" = "match" ]; then
    exit 0
fi

BODY="$(bp_request_body "$EXPECTED")"

if [ "$BP_STATUS" = "missing" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] would POST repos/$REPO/rulesets (create '$NAME')."
        exit 0
    fi
    echo "[apply] creating ruleset '$NAME' on $REPO ..."
    if printf '%s' "$BODY" | gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null; then
        echo "[OK] ruleset '$NAME' created."
        exit 0
    fi
    echo "[error] create failed." >&2
    exit 3
fi

# drift
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would PUT repos/$REPO/rulesets/$BP_RULESET_ID (reconcile '$NAME')."
    exit 0
fi

ANSWER="n"
if [ "$FORCE" -eq 1 ]; then
    ANSWER="y"
elif [ -t 0 ]; then
    printf '\nUpdate the ruleset to match the kit template? [y/N] '
    read -r ANSWER
else
    echo "[skip] non-interactive context. Re-run with --force to reconcile without a prompt."
    exit 1
fi

case "$ANSWER" in
    y|Y|yes|Yes|YES) ;;
    *) echo "[skip] ruleset left unchanged."; exit 1 ;;
esac

echo "[apply] updating ruleset '$NAME' on $REPO ..."
if printf '%s' "$BODY" | gh api -X PUT "repos/$REPO/rulesets/$BP_RULESET_ID" --input - >/dev/null; then
    echo "[OK] ruleset '$NAME' updated."
    exit 0
fi
echo "[error] update failed." >&2
exit 3
