---
status: Accepted
date: 2026-06-08
deciders: [Tetsuya]
tags: [cleanup, orphan-process, safety-filter, scheduled-task, opt-in, ux]
---

# ADR-0011: Cleanup orphan bash/gh/git subprocesses

> 本 ADR は P12 PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

Claude Code を複数の子セッションで並列運用すると (engineer-claude-kit の P1-P11 ほか多数同時稼働で発生)、各子セッションが spawn した bash / gh / git の subprocess が孤立して残る問題が判明した。特に `gh pr checks --watch` 等の watch 系コマンドは親セッション終了後も生き続け、Windows のタスクマネージャに process が溜まっていく。

手動で都度 kill するのは煩雑で、対象の選別 (active worker を誤って kill しない) も難しい。kit に組み込み、誰でも一発で安全に掃除できる手段が必要だった。

## Decision

`scripts/lib/cleanup-processes.ps1` 共通 helper を新規追加し、`/cleanup-processes` slash command + `cleanup-orphan-processes` skill として配布する (ADR-0010 の skill / command 責務分離に整合: skill = 文脈検出入口、command = 明示実行)。

- **default = 実行 (apply / kill)** — `--dry-run` (`-DryRun`) で preview に切替。初回判断の 1 ステップを省き、習慣化を妨げないため (ユーザ判断)。
- **safety filter (全て満たすもののみ kill)**:
  - 起動から 10 分以上経過 (起動直後の active worker を除外)
  - CPU 使用 5 秒未満 (idle 判定)
  - `MainWindowTitle` 空 (GUI window を持たない = background)
  - 親プロセスが IDE (VS Code / Cursor / Sublime / Atom / JetBrains) でない
  - 上記いずれかの判定に失敗 (権限不足で StartTime / CPU が読めない等) した場合は **安全側で除外** (kill しない)
- **kill 対象 = bash / gh / git のみ** (拡張可能だが default は最小)。**PowerShell 本体 (pwsh / powershell) は対象外** — cleanup 自身が PowerShell process であり、self-kill を構造的に回避する。
- **opt-in scheduled task**: `apply-claude-kit.ps1 -Global -EnableCleanupSchedule` で毎時実行の task spec を配置 (既定 OFF)。skill / command は常時配布されるが、自動 kill の timer 配置は明示 opt-in 時のみ。
- **encoding / 互換**: ADR-0003 §C 準拠 (ASCII only、PS 5.1 互換、UTF-8 no BOM)。helper は direct 実行 (scheduled / 手動) と dot-source (tests / callers) を両対応し、dot-source 時は cleanup を実行しない。
- **テスト**: 実 kill は不可逆なため Pester は injection point (`-InputProcesses` / `-Now` / `-ParentPathResolver`) と mock で完結させ、実プロセスを一切 kill しない。実機検証は DryRun のみ。

## Alternatives considered

| 案 | 内容 | 採否 |
|---|---|---|
| default = DryRun | 既定は preview、`--apply` で実行 | 否決。1 ステップ余計で習慣化しない (ユーザ判断) |
| confirmation prompt 付き | kill 前に毎回 Y/N | 否決。同上。safety filter で守る方が運用が軽い |
| より広い filter (bash を全 kill) | 条件なしで対象を一掃 | 否決。active worker の誤 kill リスク。safety filter で限定する |
| PowerShell も kill 対象に含める | pwsh / powershell も掃除 | 否決。cleanup 自身を kill する self-destruct リスク。別 Issue で慎重に検討 |

## Consequences

### 利点

- 並列運用後の孤児 process を最小操作 (`/cleanup-processes`) で一掃でき、タスクマネージャの肥大化を解消できる。
- 多段 safety filter により active worker / IDE 所有のシェルを誤って kill しない。判定不能時は安全側 (除外) に倒れる。
- skill / command は常時配布、自動 timer は opt-in に分離したため、明示的に望んだ user だけが毎時自動掃除を有効化できる。

### 欠点 / 留意

- safety filter は heuristic であり、極端なケース (10 分超 idle だが実は意味のある待機 process) を誤って kill する可能性は残る。kill 対象を bash / gh / git に限定して影響を抑える。
- scheduled-task spec の配置までは行うが、Windows Task Scheduler への自動登録は本 PR の scope 外 (登録手段は docs/setup/cleanup-processes.md に記載)。

## Refs

- ADR-0010 (skill / command 責務分離 + opt-in 設計): 本 ADR の配布形態と整合
- ADR-0007 (settings.json hands-off policy): opt-in で副作用を限定する設計思想を踏襲
- ADR-0003 §C (encoding & PS 5.1 compatibility / ASCII only)
- memory: bash から PowerShell 呼出の落とし穴 (CP932 stderr) — 孤児 process が生まれる経路の背景

## Open questions

- PowerShell process (pwsh / powershell) を対象に含めるか。self-kill 回避策 (自 PID とその祖先を除外) を設計した上で別 Issue として検討する。
- scheduled-task の Windows Task Scheduler への自動登録手段 (`Register-ScheduledTask` ラッパ等) を kit に同梱するか。需要が出れば別 ADR / Issue で検討する。
