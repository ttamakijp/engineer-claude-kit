---
name: commit-helper
description: |
  Conventional Commits 形式でコミットメッセージを生成する補助 skill。
  委譲先は config/local-llm-delegation.yaml の commit_msg に従う。
  定義が無い / 利用不可なら自分で書く (CLAUDE.md §3)。
---

# commit-helper

Conventional Commits 形式 (`<type>(<scope>): <subject>`) のコミットメッセージを生成する。

## 起動条件

ユーザが以下のいずれかを依頼したとき:
- 「コミットメッセージ作って」「commit message を生成して」
- `git diff` を見て message を提案して
- staged changes を commit する準備として message を整えて

## 実行手順

1. `~/.claude-kit/config/local-llm-delegation.yaml` の `delegation.commit_msg` を見る
2. `enabled: true` かつ `status: available` で、**diff をまだ自分の context に
   読み込んでいない** 場合のみ委譲する:
   - diff を一時ファイルへ書き出し、その **path** を `input` の指定どおり渡す
     (`diff_path`)。diff 本文を inline で渡さない
   - 返った message を提示する
3. それ以外は **自分で書く**:
   - `git diff --cached` (staged) または `git diff HEAD` (未 stage) で diff を読む
   - 修正意図を 1-2 行でユーザに確認する (diff から推定できるなら省略可)
   - Conventional Commits 形式で subject と body を書く
4. ユーザの承認後に `git commit` を実行する

## 制約

- **diff が既に context にある場合は委譲しない。** 締め出せる入力が無く、往復だけが
  増える (CLAUDE.md §3 / config の `skip_when: diff_already_in_context`)
- **Haiku sub-agent へは委譲しない。** 実測で委譲は 1 回 $0.082-0.120、自分で書くと
  $0.023-0.060 (`docs/step-6-items/item-4-subagent-cost-measurement.md`)
- 委譲先が「不明」を返した / 出力が疑わしい場合は自分が引き取る。不達時は
  Haiku へ振り直さず自分で処理する (ADR-0016 決定 B)
- `git commit` の実行は **明示承認後** のみ。skill が自動で commit しない。
  `git commit` を打つのは常に main agent 自身 (CLAUDE.md §3)
- main 直 push は禁止 (commit までで止める)
- 既存 commit-convention rule (`~/.claude/rules/commit-convention.md`) を必ず参照
