---
description: 孤立した bash / gh / git subprocess を safety filter 付きで掃除する
allowed-tools: Bash
argument-hint: "[--dry-run]"
---

# /cleanup-processes

Claude Code を複数並列で使うと、watch 系コマンド (`gh pr checks --watch` 等) が
孤立した background process として残ることがあります。このコマンドで一括掃除します。

## 引数

- (なし): **実行** (default)。対象 process を kill する
- `--dry-run`: preview のみ (kill しない、対象一覧だけ表示)

## 動作

`scripts/lib/cleanup-processes.ps1` の `Invoke-ProcessCleanup` を呼ぶ。

1. Kit が `$env:USERPROFILE\.claude-kit\` に clone されていることを確認
2. helper script を起動:
   - 引数なし → `pwsh ~/.claude-kit/scripts/lib/cleanup-processes.ps1`
   - `--dry-run` 付き → 同 script に `-DryRun` を付与
   - pwsh が無い環境では `powershell -NoProfile -File <script>` で代替実行
3. 結果 (検出数 / kill 数 / 失敗) を表示

## 安全条件

以下を **全て満たす** process のみ kill 対象:

- 起動から 10 分以上経過 (起動直後の active worker を除外)
- CPU 使用 5 秒未満 (idle 判定)
- `MainWindowTitle` 空 (GUI window を持たない = background)
- 親プロセスが IDE (VS Code / Cursor / Sublime / Atom / JetBrains) でない

kill 対象は **bash / gh / git のみ**。PowerShell 本体 (pwsh / powershell) は
対象外 (kit script 自身を kill するリスク回避)。

## 実行例

```
/cleanup-processes              # 孤立 process を掃除 (kill)
/cleanup-processes --dry-run    # 対象のプレビューのみ
```

## 注意

- kill は不可逆。初回は `--dry-run` で対象を確認してから実行を推奨
- safety filter は helper 側に hard-code されており、command からは緩められない

## Refs

- ADR-0011 (cleanup orphan processes)
