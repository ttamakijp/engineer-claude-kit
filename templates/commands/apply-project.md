---
description: 現在のプロジェクトに engineer-claude-kit を適用
allowed-tools: Bash
argument-hint: "[--dry-run|--update]"
---

# /apply-project

現在のプロジェクト（カレントディレクトリ）に engineer-claude-kit を適用する。
`/apply` と異なり、**パス指定不要** で自動的に cwd に配置される。

## 引数

- (なし): プロジェクトに適用
- `--dry-run`: 配置内容のプレビューのみ（実書き込みなし）
- `--update`: 配布前に kit 自身を fast-forward pull してから適用

## 動作

1. 現在のディレクトリが git リポジトリか確認
2. `apply-claude-kit.ps1 -Project (Get-Location)` を実行
3. `.claude/` 配下に templates が配置される

## 実行例

```
/apply-project              # cwd に配置
/apply-project --dry-run    # プレビューのみ
/apply-project --update     # kit を最新化してから cwd に配置
```

## 使い分け

| コマンド | 用途 |
|---|---|
| `/apply` | グローバル `~/.claude/` に配置、または任意パスを指定 |
| `/apply-project` | 現在のプロジェクトに自動適用（パス入力不要） |

## 注意

- 既存の `.claude/` 内ファイルが上書きされる可能性あり。`--dry-run` で事前確認を推奨
- プロジェクト CLAUDE.md ファイルが既存の場合、テンプレートでは上書きされない（ユーザ設定を尊重）
