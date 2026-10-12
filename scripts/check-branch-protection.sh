#!/usr/bin/env bash
# check-branch-protection.sh
# Report whether a repository has the kit's protect-main ruleset applied.
# Read-only: this script never writes to GitHub. Use apply-branch-protection.sh
# to create or reconcile the ruleset.
#
# Usage:
#   scripts/check-branch-protection.sh [--repo OWNER/REPO] [--name protect-main]
#                                      [--template PATH] [--path DIR]
#   --repo is inferred from the git remote of --path when omitted.
#
# Exit codes: 0 = applied (match), 1 = drift, 2 = not applied, 3 = error.
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

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo|-Repo)         REPO="${2:-}"; shift 2 ;;
        --name|-Name)         NAME="${2:-}"; shift 2 ;;
        --template|-Template) TEMPLATE="${2:-}"; shift 2 ;;
        --path|-Path)         REPO_PATH="${2:-}"; shift 2 ;;
        -h|--help)            usage; exit 0 ;;
        *) echo "[error] unknown argument: $1" >&2; usage >&2; exit 3 ;;
    esac
done

bp_require_tools || exit 3

if [ -z "$REPO" ]; then
    REPO="$(bp_repo_from_git_remote "$REPO_PATH")"
    if [ -z "$REPO" ]; then
        echo "[error] --repo was not given and no GitHub remote could be resolved from: $REPO_PATH" >&2
        echo "        Pass --repo OWNER/REPO explicitly." >&2
        exit 3
    fi
    echo "[info] repo inferred from git remote: $REPO"
fi

if [ ! -f "$TEMPLATE" ]; then
    echo "[error] ruleset template not found: $TEMPLATE" >&2
    exit 3
fi
EXPECTED="$(cat "$TEMPLATE")"

ACTUAL=""
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
exit "$(bp_exit_code)"
