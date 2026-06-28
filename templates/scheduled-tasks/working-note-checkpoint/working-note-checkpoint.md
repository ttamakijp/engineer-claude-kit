---
name: working-note-checkpoint
description: 定期的に working-note-YYYYMMDD.md を自動生成・更新する
schedule:
  cronExpression: "*/10 * * * *"
  notifyOnCompletion: false
version: 1.0.0
---

# scheduled-task: working-note-checkpoint

毎 10 分ごとに working-note チェックポイントを自動更新する。**opt-in**: `apply-claude-kit.ps1 -EnableWorkingNoteCheckpoint` を付けたときだけ `~/.claude/` 配下に配置される。

## 実行内容

`scripts/lib/auto-checkpoint.ps1` と `scripts/lib/track-workflow-state.ps1` を連続実行する。

```
pwsh -Command '. "$env:USERPROFILE\.claude-kit\scripts\lib\auto-checkpoint.ps1"; . "$env:USERPROFILE\.claude-kit\scripts\lib\track-workflow-state.ps1"'
```

pwsh 不在環境では次で代替実行する:

```
powershell -NoProfile -Command '. "$env:USERPROFILE\.claude-kit\scripts\lib\auto-checkpoint.ps1"; . "$env:USERPROFILE\.claude-kit\scripts\lib\track-workflow-state.ps1"'
```

## 動作

1. 当日の `working-note-YYYY/MM/working-note-YYYYMMDD.md` を検出 / 作成
2. 現在の session 状態を markdown 形式で append（auto-checkpoint.ps1）
3. 実行中の workflow を検出し、Active Workflows セクションを更新（track-workflow-state.ps1）
4. ファイル保存

## 設計

- **default = auto-update (実行)**。DryRun ではない (10 分ごとの自動更新が目的)
- 年月ごとにディレクトリ分離: `~/.claude/session-notes/YYYY/MM/working-note-YYYYMMDD.md`
- 同一ファイルへの並行 append は sequential lock で安全に処理
- `notifyOnCompletion: false` — 10 分ごと実行のため通知は出さない

## 有効化 / 無効化

- 有効化: `apply-claude-kit.ps1 -Global -EnableWorkingNoteCheckpoint`
- 無効化: `~/.claude/scheduled-tasks/working-note-checkpoint/` を削除して再 apply
  (`-EnableWorkingNoteCheckpoint` を付けずに apply しても既存配置は撤去しない)

Windows Task Scheduler への自動登録までは行わない (本 task spec の配置のみ)。
登録手段は `docs/setup/working-note-checkpoint.md` を参照。

## 関連

- Phase B+: session exit 時に強制 checkpoint する hook も別途配置
- CLAUDE.md § 8 (context awareness) で言及
