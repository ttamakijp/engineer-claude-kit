---
name: weekly-usage-insights
description: 週次で usage insights を生成し ~/.claude/insights/ に保存
schedule:
  cronExpression: "0 9 * * 1"
  notifyOnCompletion: false
version: 1.0.0
---

# scheduled-task: weekly-usage-insights

毎週月曜 9:00 に直近 7 日の usage insights を生成する。**既定 ON**: insights 機能は
`apply-claude-kit.ps1` で配布され、`-DisableInsights` を付けたときのみ skip される
(ADR-0014)。

## 実行内容

`scripts/usage-insights.ps1 -Window Weekly -Quiet` を実行する。

```
pwsh ~/.claude-kit/scripts/usage-insights.ps1 -Window Weekly -Quiet
```

pwsh 不在環境では次で代替実行する:

```
powershell -NoProfile -File ~/.claude-kit/scripts/usage-insights.ps1 -Window Weekly -Quiet
```

完了すると `~/.claude/insights/<YYYY-MM-DD>-weekly.md` と `latest.md` に書き出される。

## 設計

- `-Quiet` — scheduled-task 実行のため console 出力を抑止
- `notifyOnCompletion: false` — 週次実行のため通知は出さない
- 出力は `~/.claude/insights/` 配下のみ (外部送信なし)
- 解析対象は `~/.claude/projects/` の Claude Code transcript (Dispatch は scope 外)

## 有効化 / 無効化

- 有効化: 既定で配布される (`apply-claude-kit.ps1 -Global`)
- 無効化: `apply-claude-kit.ps1 -Global -DisableInsights` で配布 skip
  (既存配置は `~/.claude/scheduled-tasks/weekly-usage-insights/` を削除)

Windows Task Scheduler への自動登録までは行わない (本 task spec の配置のみ)。

## Refs

- ADR-0014 (usage insights)
