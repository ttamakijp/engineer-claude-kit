---
name: branch-protection-check
description: |
  GitHub リポジトリの branch protection ruleset (protect-main) の適用状況を確認し、
  未適用なら適用を提案する skill。新規リポジトリでの作業開始時や、リポジトリを
  新たに使い始めるときに起動する。
---

# branch-protection-check

作業対象の GitHub リポジトリに kit 標準の ruleset (`protect-main`) が適用されて
いるかを確認する。確認は **read-only**、適用は user が明示的に同意したときだけ行う
(ADR-0010 の skill / command 責務分離に整合。定期実行は `check-branch-protection`
scheduled-task 側の責務)。

## 起動条件

user が以下のいずれかに該当したとき:

- 新しい GitHub リポジトリを作成した / これから使うリポジトリを提示した
- 「branch protection」「ruleset」「main を保護」「force push を禁止したい」等に言及した
- 未知のリポジトリで最初の commit / PR 作業を始めようとしている

`match` (適用済) の場合は **報告せず黙って終わる**。正常時に session 冒頭を侵さない。

## 実行手順

1. 対象リポジトリを特定する。明示がなければ作業ディレクトリの git remote
   (`origin`) から `OWNER/REPO` を導く。GitHub remote でなければ何もしない
2. check script を実行する (read-only、書込なし):

   ```
   powershell -NoProfile -File $env:USERPROFILE\.claude-kit\scripts\check-branch-protection.ps1 -Repo <OWNER/REPO>
   ```

   - pwsh がある環境: `pwsh <kit>\scripts\check-branch-protection.ps1 -Repo <OWNER/REPO>`
   - macOS / Linux: `<kit>/scripts/check-branch-protection.sh --repo <OWNER/REPO>`

3. 出力末尾の `STATUS:` 行で分岐する:

   | STATUS | 応答 |
   |---|---|
   | `match` | 何も報告しない (または 1 行で「適用済」とだけ) |
   | `missing` | 「protect-main が未適用です。適用しますか?」と 1 行で確認 |
   | `drift` | diff を 3-5 行に要約し「kit template に合わせますか?」と確認 |

4. user が Yes のときだけ apply を実行する:

   ```
   powershell -NoProfile -File $env:USERPROFILE\.claude-kit\scripts\apply-branch-protection.ps1 -Repo <OWNER/REPO>
   ```

   まず `-DryRun` を付けて実行内容を提示してから本適用する運用でもよい。
5. 結果 (作成 / 更新 / 変更なし) を 1-3 行で報告する

## 制約

- **確認と適用を混ぜない**。check は read-only。ruleset の作成・更新は
  リポジトリ設定の変更であり、user の明示同意なしに実行しない
- `drift` を放置する選択は正当 (リポジトリ固有の意図的な差分がありうる)。
  同一 session 内で繰り返し提案しない
- `gh` 未認証 / API エラー (exit 3) のときは理由を 1 行で報告して終了し、
  ruleset の状態を推測して報告しない
- 期待値を変えたいときは skill ではなく
  `templates/branch-protection/protect-main.json` を編集する

## Refs

- `docs/branch-protection.md` (機能全体の説明、トラブルシューティング)
- ADR-0010 (skill / command 責務分離)
