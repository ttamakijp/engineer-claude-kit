# `/apply` command 引数 reference

engineer-claude-kit を現在の環境へ配布する `/apply` slash command と、その実体である
`scripts/apply-claude-kit.ps1` の引数仕様・出力・失敗時対処をまとめる。

> 入口は 3 つあるが処理は同一 (すべて `apply-claude-kit.ps1` を起動):
> - `/apply` slash command (Claude Code 内、引数を明示したいとき)
> - `apply-claude-kit` skill (Claude Code 内、自然言語で依頼するとき)
> - `apply-claude-kit.ps1` 直接呼出 (CI/CD 等、Claude Code を介さないとき)
>
> skill と command の責務分離は [templates/skills/apply-claude-kit/SKILL.md](../../templates/skills/apply-claude-kit/SKILL.md) を参照。

## 1. 引数一覧

| `/apply` での指定 | `apply-claude-kit.ps1` の引数 | 意味 | 既定 |
|---|---|---|---|
| (引数なし) | `-Global` | `~/.claude/` に配布 (全プロジェクト共通設定) | ✅ 既定 |
| `/apply <path>` | `-Project <path>` | 指定プロジェクトの `<path>/.claude/` に配布 | — |
| `/apply --dry-run` | `-DryRun` | 配置内容のプレビューのみ (実書き込みなし) | off |

- `--dry-run` は `-Global` / `-Project` のどちらとも併用可能。
  - `/apply --dry-run` → Global mode の dry-run
  - `/apply C:\dev\my-project --dry-run` → Project mode の dry-run
- `-Global` と `-Project` は排他。パスを指定すれば Project、省略すれば Global。

### 直接呼出 (Claude Code を介さない場合)

```powershell
# Global 再適用
pwsh -NoProfile -File "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Global

# プロジェクト個別配置
pwsh -NoProfile -File "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Project C:\dev\my-project

# dry-run (Project mode)
pwsh -NoProfile -File "$env:USERPROFILE\.claude-kit\scripts\apply-claude-kit.ps1" -Project C:\dev\my-project -DryRun
```

## 2. 出力例

### Global 適用 (成功時)

```
Applying engineer-claude-kit (Global mode) -> C:\Users\<you>\.claude\
  [copy] CLAUDE.md
  [copy] agents\commit-msg.md
  [copy] agents\lint-helper.md
  ...
  [copy] commands\apply.md
  [skip] work-schedule.yaml (already exists)
Wrote marker: C:\Users\<you>\.claude\.engineer-claude-kit-applied
Done. 23 files placed, 1 skipped.
```

### dry-run

```
Applying engineer-claude-kit (Global mode, DRY RUN) -> C:\Users\<you>\.claude\
  [would copy] CLAUDE.md
  [would copy] agents\commit-msg.md
  ...
  [would skip] work-schedule.yaml (already exists)
DRY RUN: no files written. 23 would be placed, 1 would be skipped.
```

> 既存ファイルの扱い (上書き / skip) は配布素材ごとに決まる。`work-schedule.yaml` など
> user 編集を想定するファイルは「既存なら skip」、kit が管理するファイルは上書きされる。
> 上書き対象を事前に把握するため、本番適用前に `--dry-run` を推奨。

## 3. 失敗時の対処

| 症状 | 原因 | 対処 |
|---|---|---|
| `apply-claude-kit.ps1 not found` | kit が clone されていない / 配置先が標準と異なる | `bootstrap.ps1` で初回 install を実施 ([README §3.1](../../README.md)) |
| `Refusing to run as Administrator` | 管理者権限で起動した | 通常ユーザ権限で再実行。どうしても必要なら `-AllowElevated` (非推奨、ADR-0008) |
| `... cannot be loaded because running scripts is disabled` | Execution Policy が `Restricted` | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` 後に再実行 ([README §3.3](../../README.md)) |
| Project mode で `<path> is not a git repository` | 指定パスが git repo でない | git repo のルートを指定するか、`git init` 後に再実行 |
| 文字化け (mojibake) した出力 | 端末 / 読込側の encoding 不一致 | kit は UTF-8 (no BOM) で出力する。PowerShell 5.1 で読む場合の対処は encoding-helper rule / ADR-0007 を参照 |

## 4. 関連

- slash command 定義: [templates/commands/apply.md](../../templates/commands/apply.md)
- skill 定義 (責務分離): [templates/skills/apply-claude-kit/SKILL.md](../../templates/skills/apply-claude-kit/SKILL.md)
- 配布スクリプト: `scripts/apply-claude-kit.ps1`
- 初回 install / 実行権限: [README §3 Quick Start](../../README.md)
