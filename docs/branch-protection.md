# Branch protection ruleset (`protect-main`)

新しく作成した / 新規に使い始める GitHub リポジトリに対し、kit 標準の branch
protection ruleset (`protect-main`) が適用されているかを確認し、未適用なら適用を
提案する機能。

確認 (check) は **read-only**、適用 (apply) は **user の明示同意が前提**。この分離が
本機能の設計の中心で、skill も scheduled-task も勝手に ruleset を書き換えない。

## 1. 目的

- 既定ブランチへの直接 push / force push / 削除を構造的に塞ぐ
- PR 経由 + linear history を既定にし、履歴を追える状態に保つ
- 上記を **リポジトリごとに手作業で設定しない** (期待値を kit が 1 箇所で持つ)

期待値の正は `templates/branch-protection/protect-main.json`。設定を変えたいときは
スクリプトではなくこの JSON を編集する。

## 2. Ruleset の内容

| 項目 | 値 | 意図 |
|---|---|---|
| `target` | `branch` | ブランチ ruleset |
| `conditions.ref_name.include` | `~DEFAULT_BRANCH` | 既定ブランチのみ対象 (main / master を問わない) |
| `enforcement` | `active` | evaluate ではなく実際に強制 |
| rule: `deletion` | — | 既定ブランチの削除を禁止 |
| rule: `non_fast_forward` | — | force push を禁止 |
| rule: `required_linear_history` | — | merge commit による履歴分岐を禁止 |
| rule: `pull_request` | 下記 | 直接 push を禁止し PR を必須化 |
| `bypass_actors` | `[]` | 例外なし (管理者も同条件) |

`pull_request` の parameters:

| parameter | 値 | 意図 |
|---|---|---|
| `required_approving_review_count` | `0` | 単独開発を止めない (PR 経由の強制が主目的) |
| `dismiss_stale_reviews_on_push` | `false` | 追加 push で approve を捨てない |
| `require_code_owner_review` | `false` | CODEOWNERS 未整備でも運用可能 |
| `require_last_push_approval` | `false` | 自分の push を自分で approve する必要をなくす |
| `required_review_thread_resolution` | `false` | 未解決コメントで merge を塞がない |
| `require_extra_approval_for_unattributed_changes` | `true` | 帰属不明な変更には追加 approve を要求 |
| `allowed_merge_methods` | `merge` / `squash` / `rebase` | 3 方式とも許可 |

> `required_approving_review_count: 0` は「レビュー不要」ではなく「**PR は必須、approve 数は
> 問わない**」という設定。1 人運用でも main への直接 push を塞げる。

## 3. 成果物

| パス | 役割 |
|---|---|
| `templates/branch-protection/protect-main.json` | 期待値の正 |
| `scripts/lib/branch-protection.ps1` | 判定ロジック (PowerShell) |
| `scripts/check-branch-protection.ps1` | 確認 (read-only) |
| `scripts/apply-branch-protection.ps1` | 作成 / 差分反映 |
| `scripts/lib/branch-protection.sh` | 判定ロジック (bash) |
| `scripts/check-branch-protection.sh` | 確認 (read-only) |
| `scripts/apply-branch-protection.sh` | 作成 / 差分反映 |
| `templates/skills/branch-protection-check/SKILL.md` | 作業開始時の自然言語入口 |
| `templates/scheduled-tasks/check-branch-protection/` | 週次 (月曜 9:00) の定期確認 |
| `tests/branch-protection.tests.ps1` | Pester (gh も network も叩かない) |

## 4. 前提

- `gh` (GitHub CLI) が install され `gh auth login` 済みであること
- 対象リポジトリに対する **admin 権限** (ruleset API は admin 必須)
- bash 版のみ追加で `jq` (1.6 以降を想定。`walk` を使用)

## 5. 実行方法

### 確認 (read-only)

```powershell
# Windows PowerShell 5.1
powershell -NoProfile -File scripts\check-branch-protection.ps1 -Repo ttamakijp/windows-shortcut-hud

# pwsh (PowerShell 7+)
pwsh scripts/check-branch-protection.ps1 -Repo ttamakijp/windows-shortcut-hud

# -Repo 省略時は -Path (既定: カレント) の git remote origin から推定
pwsh scripts/check-branch-protection.ps1
```

```bash
# macOS / Linux
scripts/check-branch-protection.sh --repo ttamakijp/windows-shortcut-hud
scripts/check-branch-protection.sh              # git remote から推定
```

出力の 3 状態と exit code:

| 状態 | 意味 | exit code |
|---|---|---|
| `match` | 適用済 (kit template と一致) | 0 |
| `drift` | 存在するが内容が異なる (差分を表示) | 1 |
| `missing` | 未適用 (同名 ruleset が存在しない) | 2 |
| — | エラー (gh 不在 / 認証失敗 / API 失敗 / repo 解決不能) | 3 |

出力の **最終行は必ず `STATUS: match|drift|missing`**。exit code に依存せず parse できる
(skill / scheduled-task はこの行で分岐する)。

### 適用

```powershell
pwsh scripts/apply-branch-protection.ps1 -Repo OWNER/REPO            # 実適用
pwsh scripts/apply-branch-protection.ps1 -Repo OWNER/REPO -DryRun    # 確認のみ
pwsh scripts/apply-branch-protection.ps1 -Repo OWNER/REPO -Force     # 差分確認を省略
```

```bash
scripts/apply-branch-protection.sh --repo OWNER/REPO
scripts/apply-branch-protection.sh --repo OWNER/REPO --dry-run
scripts/apply-branch-protection.sh --repo OWNER/REPO --force
```

挙動:

| 状態 | 動作 |
|---|---|
| `missing` | `POST repos/OWNER/REPO/rulesets` で新規作成 |
| `drift` | diff を表示し `[y/N]` で確認 → Yes なら `PUT repos/OWNER/REPO/rulesets/<id>` |
| `match` | 何もしない (exit 0) |

- `-DryRun` / `--dry-run` は **一切書込を行わない**
- `-Force` / `--force` は drift 時の確認プロンプトを省略する (自動化用)
- 非対話環境 (CI / stdin redirect) で drift かつ `-Force` 無しの場合は、
  プロンプトで hang せず exit 1 で中断する

## 6. 比較ポリシー

GitHub API が返す ruleset は、こちらが送っていない既定 parameter を含むことがある。
そのため比較は次の 2 段構えにしている:

- **rule の種類 (type) は厳密比較 (双方向)**
  期待に無い rule がリポジトリ側にあれば drift として報告する
- **rule の parameters は subset 比較**
  template が宣言した parameter のみ一致を要求し、GitHub が独自に付けた
  parameter は無視する

これを入れないと、GitHub 側の仕様追加のたびに全リポジトリが drift 扱いになる。
配列 parameter (`allowed_merge_methods` 等) は **順序を無視** して比較する。

また、比較対象は `enforcement` / `target` / `conditions.ref_name` / `rules` /
`bypass_actors` に限定し、`id` / `created_at` / `_links` 等の応答専用フィールドは
比較にも書込 body にも含めない。

## 7. 自動確認

| 入口 | タイミング | 動作 |
|---|---|---|
| `branch-protection-check` skill | 新規リポジトリでの作業開始時など (文脈検出) | check → 未適用時のみ適用を提案 |
| `check-branch-protection` scheduled-task | 毎週月曜 9:00 (opt-in) | 同上 |

どちらも `match` のときは **何も報告しない** (passive 原則: 正常時に session を侵さない)。

skill は `apply-claude-kit.ps1` で常時配布される。scheduled-task は opt-in:

```powershell
pwsh scripts/apply-claude-kit.ps1 -Global -EnableBranchProtectionSchedule
```

無効化は `~/.claude/scheduled-tasks/check-branch-protection/` を削除する
(switch を外して再 apply しても既存配置は撤去されない)。

## 8. トラブルシューティング

| 症状 | 原因 / 対処 |
|---|---|
| `GitHub CLI (gh) not found` | `gh` を install し `gh auth login` を実行 |
| `jq not found` (bash 版) | `brew install jq` / `apt-get install jq` |
| exit 3 + `HTTP 404` | リポジトリ名の誤り、または **admin 権限が無い**。ruleset API は admin 必須 |
| exit 3 + `HTTP 403` | private リポジトリで ruleset が plan 上利用できない可能性。public 化するか plan を確認 |
| `POST` が `HTTP 422` | API が未知の parameter を拒否している。`protect-main.json` から該当 parameter (例: `require_extra_approval_for_unattributed_changes`) を外して再実行 |
| 毎回 `drift` と言われる | リポジトリ固有の意図的な差分の可能性。放置してよい。恒久化するなら `protect-main.json` 側を直す |
| `-Repo` を省略すると exit 3 | remote が GitHub でない / remote 未設定。`-Repo OWNER/REPO` を明示する |

ruleset を手で確認したいときは GitHub の
`Settings > Rules > Rulesets`、または:

```bash
gh api repos/OWNER/REPO/rulesets
gh api repos/OWNER/REPO/rulesets/<id>
```

## 9. Refs

- [GitHub REST API: repository rulesets](https://docs.github.com/rest/repos/rules)
- `templates/branch-protection/protect-main.json` (期待値の正)
- ADR-0010 (skill / command 責務分離)
