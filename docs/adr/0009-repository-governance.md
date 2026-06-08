---
status: Accepted
date: 2026-06-08
deciders: [Tetsuya]
tags: [governance, branch-protection, security, ci, dogfood, github]
---

# ADR-0009: Repository governance — branch protection + leak protection dogfood + CODEOWNERS

> 本 ADR は P9 PR で起票され、②③ (leak protection dogfood / governance docs) は同 PR で実装、① (branch protection) は同 PR merge 後に gh API で適用して Accepted とする。

## Context

P8 直前の audit (session `local_317a2f9d`, 2026-06-08) で、engineer-claude-kit リポジトリのガバナンスに 3 つの欠落が判明した:

1. **main branch が完全に未保護**だった。GitHub Security 機能 (secret scanning / push protection / Dependabot) は ON だが、branch protection が一切無いため、admin による main への直 push・force push・branch 削除が技術的に可能で、CI は merge gate になっていない。
2. **kit が配布する leak protection を kit 自身で使っていない**。`templates/.gitleaks.toml` / `templates/git-hooks/pre-commit` / `templates/skills/leak-check` を user に配布しているのに、kit リポジトリ本体には gitleaks の CI gate も top-level config も無かった (ドッグフード欠如)。
3. **governance docs が未整備**。single-admin repository でありながら `.github/CODEOWNERS` / `CONTRIBUTING.md` が無く、PR review request の自動 routing や貢献ルールの明文化ができていなかった。

これは ADR-0007 (settings.json hands-off) / ADR-0008 (privilege-aware bootstrap) と同じく「kit は壊れにくく、自らの推奨を自ら守る」方針の延長線上にある。

## Decision

3 つの保護層を同時に導入する。

### 1. Branch protection (main)

PR merge **後**に `gh api -X PUT .../branches/main/protection` で以下を適用する (PR を block しないよう順序は merge 後):

- PR 経由必須 (直 push 禁止)
- 既存 CI 3 jobs + 新規 Leak Scan を required status check 化 (strict = up-to-date 必須)
- `enforce_admins = true` (admin も protection 対象、最重要)
- force push 禁止 / branch 削除禁止
- `required_linear_history = true` (squash merge 運用と整合)
- `required_conversation_resolution = true`
- approving review 数 = **0** (single-admin、reviewer 不在前提のため必須 review を要求すると self-merge で詰む)

### 2. Leak protection dogfood

- `.github/workflows/ci.yml` に `Leak Scan` job (`gitleaks/gitleaks-action@v2`、`fetch-depth: 0` で history scan) を追加し、既存 Pester / PSScriptAnalyzer job と並列実行する。
- リポジトリ top-level に `.gitleaks.toml` を新規配置する (action が config を discover できる位置)。内容は `templates/.gitleaks.toml` を踏襲しつつ、config 自身が検出 regex を literal で含むため `.gitleaks.toml` 系を allowlist に追加して自己検出を防ぐ。
- kit が配布する仕組み (gitleaks) を kit 自身でも CI gate として使う。

### 3. Governance docs

- `.github/CODEOWNERS` (single-admin、`* @ttamakijp`)
- `CONTRIBUTING.md` (workflow + hard rules summary + テスト手順 + ADR 起票ルール)

## Alternatives considered

| 案 | 内容 | 採否 |
|---|---|---|
| approving review 数 >= 1 | PR に必須 review を要求 | 否決。single-admin では self-review 不可で全 PR が詰む |
| gitleaks を pre-commit のみで運用 | CI gate を置かない | 否決。`--no-verify` でローカル bypass 可能。CI gate も必須 (多層防御) |
| `enforce_admins = false` | admin は protection 免除 | 否決。最も保護したい admin 直 push を素通しさせ、保護の意味が無い |
| CODEOWNERS なし | owner ファイルを置かない | 否決。PR review request の自動 routing が機能しない |

## Consequences

### 利点

- main への admin 直 push / force push / branch 削除を構造的に防止 (audit で判明したリスクを解消)
- 全変更が CI 4/4 緑を通過しないと merge できず、品質 gate が技術的に強制される
- kit が推奨する leak protection を kit 自身が遵守する (ドッグフードによる信頼性)
- 貢献ルールが明文化され、将来の co-maintainer 受け入れ時の前提が整う

### 欠点 / 留意

- single-admin のため緊急時の hotfix も PR + CI 経由が必須になる (`enforce_admins = true` の帰結として許容)
- branch protection 設定は repository state であり kit のコードには含まれない。設定値の source of truth は本 ADR とする
- 必須 status check 名は CI job の `name` と完全一致が必要。job rename 時は protection 設定の更新を忘れないこと

## Refs

- P9 PR (本 ADR の ②③ 実装を含む。① は同 PR merge 後に適用)
- ADR-0003 §C (encoding & PS 5.1 compatibility / ASCII only)
- ADR-0007 (settings.json hands-off policy)
- ADR-0008 (privilege-aware bootstrap)
- audit session `local_317a2f9d` (2026-06-08)
