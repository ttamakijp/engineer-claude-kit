---
name: cleanup-orphan-processes
description: |
  孤立した bash / gh / git subprocess を safety filter 付きで掃除する skill。
  並列 Claude Code 運用で残る watch 系 (gh pr checks --watch 等) の孤児 process が対象。
---

# cleanup-orphan-processes

孤立した bash / gh / git の background process を検出し、安全条件を満たすものだけを
kill する。`/cleanup-processes` slash command と同一機能の自然言語入口
(skill = 文脈検出入口、command = 明示実行)。ADR-0010 の skill / command 責務分離に整合。

## 起動条件

ユーザが以下のいずれかを依頼・言及したとき:

- 「孤立 process 掃除」「orphan process」「残った bash / gh / git を消したい」
- 「タスクマネージャに process が溜まっている」「watch が残っている」
- 複数 Claude Code 並列運用後の後始末

## 実行手順

1. Kit の helper 位置を確認: `$env:USERPROFILE\.claude-kit\scripts\lib\cleanup-processes.ps1`
2. **既定はまず DryRun** で対象を提示し、kill 前にユーザへ確認:
   - `pwsh <helper> -DryRun` (pwsh 不在なら `powershell -NoProfile -File <helper> -DryRun`)
3. ユーザが了承したら DryRun なしで再実行し、kill を適用
4. 結果 (検出数 / kill 数 / 失敗) を 1-3 行で報告

## 安全条件 (helper 側に hard-code)

以下を **全て満たす** process のみ kill 対象:

- 起動から 10 分以上経過
- CPU 使用 5 秒未満 (idle)
- `MainWindowTitle` 空 (background)
- 親プロセスが IDE (VS Code / Cursor / Sublime / Atom / JetBrains) でない

kill 対象は bash / gh / git のみ。PowerShell 本体 (pwsh / powershell) は対象外
(kit script 自身を kill するリスク回避)。

## 制約

- safety filter は helper 側に固定。skill からは緩めない
- kill は不可逆。明示依頼がない限り、まず DryRun で対象提示 → 確認 → 適用 の順
- 毎時自動実行が必要なら `apply-claude-kit.ps1 -EnableCleanupSchedule` (opt-in) を案内

## Refs

- ADR-0011 (cleanup orphan processes)
- ADR-0010 (skill / command 責務分離)
