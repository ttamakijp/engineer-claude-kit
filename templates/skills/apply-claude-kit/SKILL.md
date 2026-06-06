---
name: apply-claude-kit
description: |
  engineer-claude-kit の最新内容を ~/.claude/ または指定プロジェクトに反映する skill。
  user が「設定を更新したい」「kit を再適用」と言ったときに起動。
---

# apply-claude-kit

engineer-claude-kit リポジトリ内の SSoT (templates / config / source/rules) から、
最新の設定をユーザ環境 (~/.claude/ または <project>/.claude/) に配布する。

## 起動条件

ユーザが以下のいずれかを依頼したとき:
- 「engineer-claude-kit を適用」「設定を再反映」
- 「kit を更新したい」「最新の設定を取り込みたい」
- 新しい model ID や rule を kit から取得したい

## 実行手順

1. Kit のパスを確認:
   - `$env:ENGINEER_CLAUDE_KIT_GIT_URL` が設定されていれば、その配布元から kit を取得済と仮定
   - Kit の標準配置先: `$env:USERPROFILE\.claude-kit\`
2. `pwsh -NoProfile -File $env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1 -Global` を実行
3. (任意) 現在の作業ディレクトリが git repo なら、`apply-claude-kit.ps1 -Project (Get-Location)` も提案
4. 結果を user に報告: 配置されたファイル数 / 配置先パス / marker JSON の生成確認

## 制約

- Kit が clone されていない場合は、`bootstrap.ps1` の実行を促す
- ASCII only PowerShell 規約 (ADR-0003 §C) に従い、エラーメッセージは英語
- 重要判断 (rollback / 既存設定上書き) は必ず user 確認後に実行
- `-DryRun` モードを先に試して、変更箇所を user に提示してから実適用を推奨
