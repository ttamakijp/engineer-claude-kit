# Settings Hooks Configuration Examples

このドキュメントは、Claude Code の `settings.json` に **hooks** (フック) を設定して、自動的にバックグラウンドプロセスをクリーンアップする手順を示します。

## 背景: zombie process の累積問題

Windows 上で Claude Code を並列実行すると、bash.exe / git.exe / gh.exe subprocess が完全に終了せず、suspended (中断) 状態で累積します。

理由:

- Windows での paipelined subprocess が SIGTERM を正しく伝播しない
- 複数 tool call の並列実行で、メインプロセス終了後も child process が block したまま
- Task Manager で「sleeping」「suspended」プロセスが増加

症状:

```
Task Manager で bash/git/gh が dozens of プロセスで残る
→ メモリ: 1MB 未満/プロセス (軽微)
→ ハンドル数: 累積で increase (リソースリーク)
→ ディスク I/O スケジューラに spam (watchdog / timer block)
```

## 解決策: PostToolBatch hook による自動クリーンアップ

Claude Code の `settings.json` に hook を設定し、**tool call batch 終了ごとに orphaned process を検出・掃除** できます。

### 1. Hook 設定例（基本形）

`~/.claude/settings.json` に以下を追加してください:

```json
{
  "hooks": {
    "PostToolBatch": [
      {
        "shell": "powershell",
        "command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude-kit\\scripts\\lib\\cleanup-processes.ps1\"; Invoke-ProcessCleanup -IdleMinutes 5 -MaxCpuSeconds 2.0'"
      }
    ]
  }
}
```

### 2. パラメータ調整

cleanup-processes.ps1 は以下の safety filter を適用します。調整可能:

| パラメータ | デフォルト | 意味 | 調整例 |
|---|---|---|---|
| `-IdleMinutes` | 10 | プロセス開始から N 分以上経過したもののみ kill | 短期: 5 分、長期: 30 分 |
| `-MaxCpuSeconds` | 5.0 | CPU 使用時間が N 秒以下（idle）のもののみ kill | 短期: 2.0、長期: 10.0 |

より**激進的に**クリーンアップする場合 (短い idle threshold):

```json
"command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude-kit\\scripts\\lib\\cleanup-processes.ps1\"; Invoke-ProcessCleanup -IdleMinutes 5 -MaxCpuSeconds 2.0'"
```

より**保守的に** (長い idle threshold、active worker を保護):

```json
"command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude-kit\\scripts\\lib\\cleanup-processes.ps1\"; Invoke-ProcessCleanup -IdleMinutes 30 -MaxCpuSeconds 5.0'"
```

### 3. Safety Filter (何が kill されるか / されないか)

以下のプロセスは**絶対に kill されません**:

- 起動から 5 分以内（-IdleMinutes 内）
- CPU 使用時間が 2+ 秒（active worker）
- MainWindowTitle がある（GUI terminal = IDE 内 shell）
- 親プロセスが IDE (VS Code / Cursor / JetBrains)

つまり、同時実行中の bash / git は保護されます。

### 4. 既存 settings.json への統合

既に `settings.json` が存在する場合、`hooks` key を追加してください:

```json
{
  "theme": "dark",
  "autoUpdatesChannel": "latest",
  "hooks": {
    "PostToolBatch": [
      {
        "shell": "powershell",
        "command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude-kit\\scripts\\lib\\cleanup-processes.ps1\"; Invoke-ProcessCleanup -IdleMinutes 5 -MaxCpuSeconds 2.0'"
      }
    ]
  }
}
```

### 5. 動作確認

設定後、以下を試してください:

```powershell
# dry-run で何が kill されるかを確認（実際には kill しない）
powershell -NoProfile -Command '. "$env:USERPROFILE\.claude-kit\scripts\lib\cleanup-processes.ps1"; Invoke-ProcessCleanup -DryRun'

# 実際に cleanup を実行
powershell -NoProfile -Command '. "$env:USERPROFILE\.claude-kit\scripts\lib\cleanup-processes.ps1"; Invoke-ProcessCleanup'
```

### 6. トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| hook が実行されない | path が wrong、または `-NoProfile` で script location が見つからない | `$USERPROFILE` を展開して絶対 path を確認 |
| "cannot be loaded because running scripts is disabled" | PowerShell execution policy | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| hook が error を出力 | cleanup-processes.ps1 が not found または syntax error | path が `~/.claude-kit/` にあるか確認、pwsh version を確認 (5.1+) |
| cleanup が bash/git 中の process を kill | safety filter が loose すぎる | `-IdleMinutes` を増やす (デフォルト 10 → 30) |

### 7. 手動実行 (Skill: cleanup-processes)

hook 不要で即座にクリーンアップしたい場合:

```
/cleanup-processes
```

この skill は上記と同じ cleanup-processes.ps1 を呼び出します。hook との併用可。

## 設計判断 (ADR-0011)

本ドキュメントの background と safety filter 詳細は **ADR-0011: Orphaned process cleanup** に記載されています。

参照: `docs/adr/0011-*.md`

## Related

- **ADR-0007**: settings.json の hands-off ポリシー
- **ADR-0010**: interactive settings wizard
- **ADR-0011**: (TBD) Orphaned process cleanup と safety filter 設計
- **Skill**: `/cleanup-processes` — 手動実行用
