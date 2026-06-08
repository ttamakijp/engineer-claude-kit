---
name: cleanup-orphan-processes
description: 孤立した bash / gh / git プロセスを 1 時間ごとに掃除
schedule:
  cronExpression: "0 * * * *"
  notifyOnCompletion: false
version: 1.0.0
---

# scheduled-task: cleanup-orphan-processes

毎時 0 分に孤立 process cleanup を実行する。**opt-in**: `apply-claude-kit.ps1
-EnableCleanupSchedule` を付けたときだけ `~/.claude/` 配下に配置される。

## 実行内容

`scripts/lib/cleanup-processes.ps1` を引数なし (= apply / kill) で起動する。

```
pwsh ~/.claude-kit/scripts/lib/cleanup-processes.ps1
```

pwsh 不在環境では次で代替実行する:

```
powershell -NoProfile -File ~/.claude-kit/scripts/lib/cleanup-processes.ps1
```

## 設計

- **default = apply (実行)**。DryRun ではない (毎時の自動掃除が目的)
- safety filter は helper 側に hard-code:
  - 起動から 10 分以上経過 / CPU 5 秒未満 / MainWindow 空 / 親が IDE でない
  - kill 対象は bash / gh / git のみ (PowerShell 本体は対象外)
- `notifyOnCompletion: false` — 毎時実行のため通知は出さない

## 有効化 / 無効化

- 有効化: `apply-claude-kit.ps1 -Global -EnableCleanupSchedule`
- 無効化: `~/.claude/scheduled-tasks/cleanup-orphan-processes/` を削除して再 apply
  (`-EnableCleanupSchedule` を付けずに apply しても既存配置は撤去しない)

Windows Task Scheduler への自動登録までは行わない (本 task spec の配置のみ)。
登録手段は `docs/setup/cleanup-processes.md` を参照。

## Refs

- ADR-0011 (cleanup orphan processes)
