---
name: check-branch-protection
description: 使用中のリポジトリで protect-main ruleset が適用されているか確認
schedule:
  cronExpression: "0 9 * * MON"
  notifyOnCompletion: true
version: 1.0.0
---

# scheduled-task: check-branch-protection

毎週月曜 9:00 に、作業対象リポジトリの GitHub branch protection ruleset
(`protect-main`) が適用されているかを確認する。**opt-in**: `apply-claude-kit.ps1
-EnableBranchProtectionSchedule` を付けたときだけ `~/.claude/` 配下に配置される。

確認は read-only。適用は user が明示的に Yes と答えたときだけ行う。

## 実行内容

1. 対象リポジトリを特定する
   - このタスクを起動した作業ディレクトリの git remote (`origin`) から `OWNER/REPO` を導く
   - remote が GitHub でない / 解決できない場合は **何もせず終了** (報告不要)
2. check script を実行する (read-only)

   ```
   powershell -NoProfile -File ~/.claude-kit/scripts/check-branch-protection.ps1 -Repo <OWNER/REPO>
   ```

   pwsh がある環境では `pwsh ~/.claude-kit/scripts/check-branch-protection.ps1 -Repo <OWNER/REPO>`、
   macOS / Linux では `~/.claude-kit/scripts/check-branch-protection.sh --repo <OWNER/REPO>`。

3. 出力末尾の `STATUS:` 行で分岐する

   | STATUS | 応答 |
   |---|---|
   | `match` | **何も報告しない** (passive 原則。正常時に session を侵さない) |
   | `missing` | 「protect-main が未適用です。適用しますか?」と 1 行で質問 |
   | `drift` | diff を 3-5 行に要約し「kit template に合わせますか?」と質問 |

4. user が Yes と答えた場合のみ apply script を実行する

   ```
   powershell -NoProfile -File ~/.claude-kit/scripts/apply-branch-protection.ps1 -Repo <OWNER/REPO>
   ```

   No / 無応答なら何もしない。`drift` を放置する選択も正当 (リポジトリ固有の
   意図的な差分がありうる) ので、再確認を繰り返さない。

## 設計

- **read-only が既定**。書込 (POST / PUT) は user の明示同意が前提
- `gh` 未認証 / API 失敗 (exit 3) の場合は 1 行だけ理由を報告して終了。
  ruleset の状態を推測して報告しない
- `notifyOnCompletion: true` — 週次かつ `missing` / `drift` 時のみ user 操作を
  要するため、完了通知を出す
- 同等の確認を session 冒頭に行いたい場合は `branch-protection-check` skill を使う
  (skill = 文脈検出入口、scheduled-task = 定期実行)

## 有効化 / 無効化

- 有効化: `apply-claude-kit.ps1 -Global -EnableBranchProtectionSchedule`
- 無効化: `~/.claude/scheduled-tasks/check-branch-protection/` を削除して再 apply
  (switch を外して apply しても既存配置は撤去しない)

## Refs

- `docs/branch-protection.md` (機能全体の説明)
- `templates/branch-protection/protect-main.json` (期待値の正)
