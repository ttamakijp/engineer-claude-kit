# Tier 2: Session 中断・復帰の自動化（Phase B+: working-note-checkpoint）

## 背景

複数 agent 処理（deep-research workflow など）の途中で PC shutdown が発生した場合、**中間データ（検索結果、API レスポンス、agent 出力）が全て lost** される。再開時に「ゼロから」スタートしなければならない。

## 仕様

### Tier 1: 定期自動 checkpoint + exit hook

- cron job が 10 分ごとに working-note に state 記録
- session exit 時に強制 checkpoint で最後の 1 秒も capture
- 最大 loss = 最後の auto-checkpoint 以降（通常 < 10 分）

### Tier 2: Workflow state 自動復帰

- track-workflow-state.ps1 が active workflows を検出
- working-note の `## Active Workflows` セクションに runId を記録
- Workflow tool の `resumeFromRunId` feature で中間データ保持のまま resume

### Tier 3: 起動時の自動復帰提案

- Claude が起動時に working-note から Active Workflows を検出
- 「前回の deep-research は phase 2/5 で中断。resume しますか？」と提案
- user が同意 → `Workflow({scriptPath, resumeFromRunId})` で自動 continue
- 中間データは全て preserved（lost なし）

## 有効化

デフォルトで有効化 + 自動設定：
```powershell
apply-claude-kit.ps1 -Global
```

実行すると自動的に以下が行われます：
- `~/.claude/settings.json` に on-exit hook を追加（既存設定は上書きしない）
- Windows Task Scheduler に 10 分ごとの cron job を登録

無効化する場合：
```powershell
apply-claude-kit.ps1 -Global -DisableWorkingNoteCheckpoint
```

## 保存先・関連ファイル

- `~/.claude/session-notes/YYYY/MM/working-note-YYYYMMDD.md` — 進捗 + Active Workflows metadata
- `~/.claude/transcript/agent-*.jsonl` — Workflow tool が自動管理（中間データ）
- `~/.claude/scheduled-tasks/working-note-checkpoint/` — cron job spec（reference のみ）
- `~/.claude/hooks/on-session-exit-checkpoint.ps1` — exit hook
- `~/.claude/settings.json` — on-exit hook setting（apply-claude-kit が自動追加）

## 保証事項

### 中間データの完全保持

- Workflow tool が state journal (`~/.claude/transcript/agent-*.jsonl`) に中間結果を自動保存
- API 呼び出し結果、検索結果、前段階の agent 出力も全て preserved
- 中間データ loss は発生しない（resumeFromRunId が有効である限り）

### 中断時点からの復帰保証

- `resumeFromRunId` で指定した workflow は、最後に完了した agent() 直後から復帰
- completed phase の agent() は cache から即座に復帰（再実行しない）
- 次の uncompleted phase だけが新規実行される
- つまり「昨日 phase 2/5 で中断」なら、「phase 3 から新規実行」（phase 1-2 の中間データ保持）

## セットアップ失敗時

もし `apply-claude-kit.ps1 -Global` 実行中に setup step が失敗した場合、以下で手動実行できます：

```powershell
# setup-working-note.ps1 を手動実行
pwsh ~/.claude-kit/scripts/lib/setup-working-note.ps1
```

または、`~/.claude/examples/settings-hooks-working-note.example.md` を参照して手動設定。

## 注意事項

1. **Workflow の中間データは Workflow tool が自動管理（user 不要）**
   - user は何もしなくてよい
   - 複数言語・複数 phase の workflow でも state journal から自動復帰
   - 中間データ loss は発生しない

2. **Settings.json merge について**
   - apply-claude-kit の setup step は merge only（既存項目は上書きしない）
   - on-exit hook section のみ追加（他の hooks は保持）

3. **Windows Task Scheduler 権限**
   - cron job 登録には管理者権限が必要な場合あり
   - 登録失敗時も functioning には影響なし（手動で登録可能）

設定後は、**user は何もしない**。PC が落ちても、次回起動時に自動復帰される。

## 関連

- Rule: `auto-load-working-note.md` — 起動時の自動 load
- Rule: `auto-resume-workflow.md` — workflow resume 提案
- Script: `auto-checkpoint.ps1` — session state append
- Script: `track-workflow-state.ps1` — workflow metadata update
- ADR-0015 (TBD): Session interruption recovery & workflow resume design
