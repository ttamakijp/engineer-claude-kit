# Cleanup orphan processes (`/cleanup-processes`)

Claude Code を複数の子セッションで並列運用すると、各セッションが spawn した
bash / gh / git の subprocess が孤立して残ることがある。特に `gh pr checks --watch`
等の watch 系コマンドは親セッション終了後も生き続け、Windows のタスクマネージャに
process が溜まっていく。本機能はそれを safety filter 付きで一括掃除する。

設計の根拠は [ADR-0011](../adr/0011-cleanup-orphan-processes.md) を参照。

## 起動方法

| 入口 | 用途 |
|---|---|
| `/cleanup-processes` | Claude Code 内で明示実行 (default = kill) |
| `/cleanup-processes --dry-run` | preview のみ (kill しない) |
| `cleanup-orphan-processes` skill | 自然言語起動 (「孤立 process を掃除」等)。まず DryRun 提示 → 確認 → 適用 |
| helper を直接実行 | `pwsh ~/.claude-kit/scripts/lib/cleanup-processes.ps1 [-DryRun]` |

pwsh が未 install の環境では `powershell -NoProfile -File <helper>` で代替実行できる
(helper は PS 5.1 互換)。

## Safety filter

以下を **全て満たす** process のみ kill 対象となる (helper 側に hard-code、緩められない):

| 条件 | 既定値 | 意図 |
|---|---|---|
| 起動からの経過時間 | 10 分以上 | 起動直後の active worker を除外 |
| CPU 使用時間 | 5 秒未満 | busy な worker を除外 (idle 判定) |
| `MainWindowTitle` | 空 | GUI window を持つ terminal を除外 (background のみ) |
| 親プロセス | IDE でない | VS Code / Cursor / Sublime / Atom / JetBrains 配下を除外 |

- 判定に失敗した場合 (権限不足で `StartTime` / `CPU` が読めない等) は **安全側で除外** (kill しない)。
- kill 対象は **bash / gh / git のみ**。**PowerShell 本体 (pwsh / powershell) は対象外** で、
  cleanup 自身を kill する self-kill を構造的に回避する。

しきい値を変える必要があれば helper を直接呼び、引数で上書きできる:

```powershell
pwsh ~/.claude-kit/scripts/lib/cleanup-processes.ps1 -IdleMinutes 30 -MaxCpuSeconds 2 -DryRun
```

## 自動化 (opt-in scheduled task)

毎時自動で掃除したい場合は、apply 時に `-EnableCleanupSchedule` を付ける (既定 OFF):

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Global -EnableCleanupSchedule
```

これにより task spec が `~/.claude/scheduled-tasks/cleanup-orphan-processes/` に配置される
(`cronExpression: "0 * * * *"`、default = apply)。skill / command 自体は
`-EnableCleanupSchedule` の有無に関わらず常時配布される。

### Windows Task Scheduler への登録

task spec の配置までが kit の責務で、Windows Task Scheduler への登録は手動で行う
(本 PR の scope 外)。毎時実行を登録する例:

```powershell
$action  = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-NoProfile -File `"$env:USERPROFILE\.claude-kit\scripts\lib\cleanup-processes.ps1`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName "eck-cleanup-orphan-processes" `
    -Action $action -Trigger $trigger -Description "engineer-claude-kit: cleanup orphan bash/gh/git"
```

> pwsh 不在環境では `-Execute "powershell.exe"` に置き換える。
> 登録解除は `Unregister-ScheduledTask -TaskName "eck-cleanup-orphan-processes" -Confirm:$false`。

### 無効化

- scheduled-task spec の撤去: `~/.claude/scheduled-tasks/cleanup-orphan-processes/` を削除
  (`-EnableCleanupSchedule` を付けずに再 apply しても既存配置は撤去しない)。
- Task Scheduler 登録の解除: 上記 `Unregister-ScheduledTask`。

## 注意

- kill は不可逆。初回は `--dry-run` で対象を確認してから実行することを推奨。
- safety filter は helper 側に固定されており、command / skill からは緩められない。
