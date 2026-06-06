---
description: 現在の session 状態を markdown checkpoint に保存する
allowed-tools: Bash, Read, Write, Grep, Glob
argument-hint: "[任意の本文 / 省略で Claude 自動要約]"
---

# /checkpoint

現在の session 状態を checkpoint markdown として保存する。日跨ぎ / 端末切替 / `/clear` 前の context 保全に使う。

## 動作

1. **保存場所の解決**:
   - bash で `git rev-parse --show-toplevel 2>/dev/null` を実行
   - 成功 (project root 検出) → `<project>/.claude/checkpoints/`
   - 失敗 (project 外) → `~/.claude/checkpoints/` (Windows: `$env:USERPROFILE\.claude\checkpoints\`)
   - 保存 dir が無ければ `mkdir -p` 相当で作成

2. **要約の作成** (引数なしの場合):
   - 直近の会話・編集ファイル・決定事項を **small-fast model (Haiku 4.5)** で要約
   - small-fast 指定方法: 設計上は ADR-0004 (auto model routing) に従う
   - 引数があれば手動本文を優先 (`$ARGUMENTS` を要約の代わりに使用)

3. **markdown の生成**:
   - ファイル名: `<YYYYMMDD-HHMMSS>-<short-slug>.md` (slug は要約 title から kebab-case)
   - スキーマ (ADR-0005 で確定):
     ```markdown
     ---
     session_id: null
     created_at: <ISO 8601 with timezone>
     project_path: <絶対パス or null>
     title: <kebab-case slug>
     tags: []
     ---

     ## 目的

     <要約 1-3 行>

     ## 直近の作業内容

     <3-5 行>

     ## 触ったファイル

     - <path>
     - <path>

     ## 決定事項 / 設計判断

     <該当あれば>

     ## 次のアクション

     <該当あれば>

     ## 関連 commit / branch / PR

     <該当あれば>
     ```
   - `created_at` は ISO 8601 + timezone (例: `2026-06-07T17:45:00+09:00`)
   - `project_path` は `git rev-parse --show-toplevel` の絶対パス、project 外なら null
   - `session_id` は Claude Code session ID が取得不能なら null (ADR-0005 で議論)

4. **書き込み + 報告**:
   - Write tool で markdown を保存
   - 保存パスを user に 1 行で報告: 「✅ Checkpoint saved: <path>」
   - 機密情報 (`.env*` / secrets) 検出時は **マスクして** 書き込む (ADR-0005 Open question)

## 制約

- 機密 (PII / credentials) を要約に含めない
- 保存場所が存在しない・書込権限なし → エラー報告して中断
- 既存ファイルの上書き禁止 (同 timestamp の衝突は milliseconds 追加で回避)

## Refs

- ADR-0005 (`/checkpoint` `/resume` 設計)
- ADR-0004 (auto model routing)
