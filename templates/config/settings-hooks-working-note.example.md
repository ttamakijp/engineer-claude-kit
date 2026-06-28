# Working Note Session Exit Checkpoint Hook Configuration

このドキュメントは、Claude Code の `settings.json` に **session-exit hook** を設定して、session 終了時に自動的に `working-note-YYYYMMDD.md` をチェックポイントする手順を示します。

## 背景: PC 予期しない shutdown 時の復旧

複数の session で以下のシナリオが想定されます:

- 重い実装中に PC がシャットダウン
- session の中断時点がどこかが不明
- 復帰時に「昨日のどこまで終わったのか」を思い出すのに時間がかかる

**解決策**: session exit 時に自動 checkpoint を記録し、次回起動時に自動復帰を提案

## 設定手順

### 1. Hook 設定例（基本形）

`~/.claude/settings.json` に以下を追加してください:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "type": "command",
        "command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude\\hooks\\on-session-exit-checkpoint.ps1\"'"
      }
    ]
  }
}
```

### 2. 既存 settings.json への統合

既に `settings.json` が存在する場合、`hooks` key に `SessionEnd` を追加してください:

```json
{
  "theme": "dark",
  "autoUpdatesChannel": "latest",
  "hooks": {
    "SessionEnd": [
      {
        "type": "command",
        "command": "powershell -NoProfile -Command '. \"$env:USERPROFILE\\.claude\\hooks\\on-session-exit-checkpoint.ps1\"'"
      }
    ]
  }
}
```

### 3. 動作確認

設定後、Claude session を終了してください。以下の location に `working-note-YYYYMMDD.md` ファイルが生成 / 更新されます:

```
~/.claude/session-notes/YYYY/MM/working-note-YYYYMMDD.md
```

例:

```
~/.claude/session-notes/2026/06/working-note-20260618.md
```

ファイル末尾に `**Session exit at 2026-06-18 16:15:32 (normal)**` というマーカーが追記されていれば、hook は正常に実行されました。

### 4. Scheduled Auto-checkpoint との併用

本 hook は **Phase B+** の一部です。同時に以下も有効化してください:

```powershell
# 定期 checkpoint（10 分ごと） + session exit hook の両方を有効化
apply-claude-kit.ps1 -Global -EnableWorkingNoteCheckpoint
```

この場合、以下の flow が動作します:

| タイミング | 実行内容 | 保存先 |
|----------|--------|--------|
| **10 分ごと** | auto-checkpoint scheduled task が state を append | `working-note-YYYYMMDD.md` |
| **session exit** | on-exit hook が最終状態を記録 | 同一ファイルに `**Session exit at ...` を append |
| **次回起動** | Claude が自動 load し「昨日のここから」と提案 | context に embed |

### 5. トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| hook が実行されない | path が wrong、または `-NoProfile` で script が見つからない | `$USERPROFILE` を展開して絶対 path を確認 |
| "on-session-exit-checkpoint.ps1: The term is not recognized" | hook file が deployed されていない | `apply-claude-kit.ps1 -Global -EnableWorkingNoteCheckpoint` を実行 |
| "cannot be loaded because running scripts is disabled" | PowerShell execution policy | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| working-note ファイルが生成されない | file path 権限不足 | `~/.claude/session-notes/` ディレクトリが writable か確認 |

### 6. Hook 無効化

session-exit hook を無効化する場合、settings.json から `SessionEnd` key を削除してください:

```json
{
  "hooks": {
    // "SessionEnd": [ ... ] を削除
  }
}
```

定期 checkpoint (cron job) は別途 `apply-claude-kit.ps1` の `-EnableWorkingNoteCheckpoint` flag で管理されます。

## 設計判断

- **Phase B+** では exit hook で最後の 1 秒も capture
- scheduled task (10 分ごと) との両立で、最大 loss = 最後の exit hook 失敗時のみ
- markdown format なので git history に artifact として残る
- 起動時の auto-load rule で user は何もしなくてよい

## Related

- **CLAUDE.md § 8**: context awareness / working-note-checkpoint
- **auto-load-working-note.md**: 起動時の自動 detect + 復帰提案
- **scheduled-task: working-note-checkpoint**: 定期 (10 分ごと) auto-checkpoint
