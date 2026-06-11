---
description: Show usage insights from ~/.claude/insights/
allowed-tools: Bash, Read
argument-hint: "[--window daily|weekly] [--regenerate] [--ack]"
---

# /insights

`usage-insights` skill を起動して直近の usage insights を表示します。
Claude Code transcript を解析した model 効率 / cache 効率 / token 浪費 / stuck
パターン / Haiku 委譲率 / cost trend のレポートです。

## オプション

- `--window weekly` (デフォルト): 週次レポート (直近 7 日)
- `--window daily`: 日次レポート (直近 1 日)
- `--regenerate`: キャッシュを使わず再生成
- `--ack`: 現在の insights を確認済 (acked) としてマーク (次回まで非表示)

## 動作

1. Kit が `$env:USERPROFILE\.claude-kit\` に clone されていることを確認
2. `--regenerate` 指定時、または `~/.claude/insights/latest.md` が無い場合は再生成:
   - `pwsh ~/.claude-kit/scripts/usage-insights.ps1 -Window <Window>`
   - pwsh が無い環境では `powershell -NoProfile -File <script> -Window <Window>`
3. `~/.claude/insights/latest.md` を read し、**Key findings** を要約して提示
4. `--ack` 指定時は `~/.claude/insights/.acked` を touch (timestamp 更新) し、
   次回 session 開始時の自動提示を抑止

## 実行例

```
/insights                      # 週次 insights を表示
/insights --window daily       # 日次 insights を表示
/insights --regenerate         # 再生成してから表示
/insights --ack                # 現在の insights を確認済にする
```

## 注意

- pricing は `scripts/pricing.psd1` の概算 (web 確認待ち、相対比較用)
- 解析対象は `~/.claude/projects/` のみ (Dispatch transcript は scope 外)

## Refs

- ADR-0014 (usage insights)
