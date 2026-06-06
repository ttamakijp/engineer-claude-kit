---
description: 前回の checkpoint から session を再開する
allowed-tools: Bash, Read, Glob
argument-hint: "[checkpoint slug or 省略で最近 5 件から選択]"
---

# /resume

`.claude/checkpoints/` から checkpoint markdown を読込み、現在の session の context として復元する。

## 動作

1. **保存場所の解決**:
   - bash で `git rev-parse --show-toplevel 2>/dev/null` を実行
   - project root 検出 → `<project>/.claude/checkpoints/`
   - 失敗 → `~/.claude/checkpoints/`
   - 両方探索する場合は project 優先

2. **引数の処理**:
   - `$ARGUMENTS` が空 → 最近 5 件モード
   - `$ARGUMENTS` が指定 → slug マッチで 1 件選択

3. **最近 5 件モード**:
   - Glob で `*.md` を取得 (mtime 降順 sort)
   - 上位 5 件を番号付きで表示:
     ```
     1. 2026-06-07 17:45 — phase-2-final-completion
        場所: C:\Users\t_tamaki\engineer-claude-kit
        要約: ... (1 行)
     2. 2026-06-07 12:30 — adr-0005-draft-checkpoint-resume
        ...
     ```
   - user の番号入力を待つ
   - 入力された番号の checkpoint を読込

4. **slug 指定モード**:
   - `*.md` の中で slug (filename 末尾) が部分一致するものを検索
   - 複数 hit → 最新を選択 (+ 警告)
   - 1 件 hit → そのまま読込
   - 0 件 → エラー報告

5. **context への注入**:
   - Read tool で checkpoint markdown を読込
   - 内容を assistant message として user に提示:
     ```
     📖 Resumed from: <path>

     <markdown 本文をそのまま貼付>

     ---
     ✅ Context loaded. 次のアクションを進めてください。
     ```
   - user の次の prompt から、この context を踏まえて応答

## 制約

- checkpoint が存在しない → 「No checkpoints found at <path>」と報告して終了
- 機密情報を含む可能性のあるパスを user 出力する際は path のみで内容を露出させない (ファイル自体の中身は別途 Read で取得)
- 機密マスクの解除は行わない (checkpoint 時点でマスクされた値はそのまま)

## Refs

- ADR-0005 (`/checkpoint` `/resume` 設計)
