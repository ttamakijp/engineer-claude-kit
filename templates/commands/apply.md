---
description: engineer-claude-kit を現在の環境に適用 (apply-claude-kit.ps1 を起動)
allowed-tools: Bash
---

# /apply

engineer-claude-kit の最新内容を `~/.claude/` (グローバル) または指定プロジェクトに配布する。

## 引数

- `$1` (任意): プロジェクトパス。省略時は `-Global` モード (`~/.claude/` に配置)
- `--dry-run`: 配置内容のプレビューのみ実行 (実書き込みなし)
- `--update`: 配布前に kit 自身を origin に fast-forward pull (ADR-0013)。
  起動時の behind 検出 + hint は常時動作し、`--update` 指定時のみ実 pull する

## 動作

1. Kit が `$env:USERPROFILE\.claude-kit\` に clone されていることを確認
2. `apply-claude-kit.ps1` を引数に応じて起動:
   - 引数なし → `-Global`
   - パス指定 → `-Project <path>`
   - `--dry-run` 付き → `-DryRun` フラグ追加
   - `--update` 付き → `-Update` フラグ追加 (kit を fast-forward pull)
3. 結果 (配置ファイル数、marker JSON パス、エラー有無) を表示

## 実行例

```
/apply                          # ~/.claude/ に Global 配置
/apply C:\dev\my-project        # 指定プロジェクトに配置
/apply --dry-run                # Global mode の dry-run
/apply --update                 # kit を最新化してから Global 配置
```

## 注意

- 既存の `~/.claude/` 内ファイルが上書きされる可能性あり。`--dry-run` で事前確認を推奨
- Bedrock 環境想定 (Sonnet 4.5 main + Haiku 4.5 small fast の placeholder が substitution される)
