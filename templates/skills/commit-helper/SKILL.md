---
name: commit-helper
description: |
  Conventional Commits 形式でコミットメッセージを生成する補助 skill。
  軽作業のため commit-msg sub-agent (Haiku 4.5) を Task tool で起動して委譲する。
---

# commit-helper

Conventional Commits 形式 (`<type>(<scope>): <subject>`) のコミットメッセージを生成する。

## 起動条件

ユーザが以下のいずれかを依頼したとき:
- 「コミットメッセージ作って」「commit message を生成して」
- `git diff` を見て message を提案して
- staged changes を commit する準備として message を整えて

## 実行手順

1. `git diff --cached` (staged) または `git diff HEAD` (未 stage) で対象 diff を取得
2. ユーザに修正意図 (1-2 行) を確認 (省略可、diff から推定可能なら skip)
3. **Task tool** で `commit-msg` sub-agent (Haiku 4.5) を起動し、以下を渡す:
   - `git diff` 結果 (全文または要約)
   - 修正意図 (取得できた場合)
4. sub-agent の返した message を提示し、ユーザの承認後に `git commit -m "<message>"` を実行する

## 制約

- `commit-msg` sub-agent が「不明」と返した場合、main agent (Sonnet 4.5) が引き取り、ユーザに追加情報を求める
- `git commit` の実行は **明示承認後** のみ。skill が自動で commit しない
- main 直 push は禁止 (commit までで止める)
- 既存 commit-convention rule (`~/.claude/rules/commit-convention.md`) を必ず参照
