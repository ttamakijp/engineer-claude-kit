# engineer-claude-kit bootstrap 動作検証手順書

**関連**: Phase 1 (config + build-rules), Phase 2 (templates + apply + bootstrap), Phase 3.1 (common skills), Phase 3.2 (cost-observe)

本書は Phase 1-3 で実装した bootstrap chain を Windows 環境で検証する手順を定める。Claude MAX 20x 契約環境 (AWS Bedrock アクセスなし) でも実施可能な範囲を明示する。

## 必要環境

| # | 必須 | 用途 | MAX 環境で必要か |
|---|---|---|---|
| 1 | Windows PC (PowerShell 5.1 or 7.x) | bootstrap.ps1 実行 | OK |
| 2 | git (GitHub アクセス) | 本リポ clone | OK |
| 3 | インターネット接続 | git + 実 Claude セッション (V5 adapted) | OK |
| 4 | Claude Code CLI 本体 | V5 で実セッションテスト時 | COND MAX 契約で利用可 |
| 5 | AWS Bedrock credentials (`aws configure` 済) | V5 / V6 の本来想定 | NG Bedrock SKIP |
| 6 | 任意の git project dir (空でも可) | -Project mode の対象 | OK |

**推奨**: 既存の `~/.claude/` を汚さないため **clean Windows 環境** (VM / 別 PC / 退避済 backup) での実施を推奨。

## 事前準備

### A. 既存 `~/.claude/` のバックアップ (clean 環境でない場合)

```powershell
# 既存ファイルを保護
if (Test-Path "$env:USERPROFILE\.claude") {
    Copy-Item -Recurse "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Write-Host "Backed up existing ~/.claude/"
}
```

### B. リポを clone

```powershell
cd $env:USERPROFILE
git clone https://github.com/ttamakijp/engineer-claude-kit.git .claude-kit
cd .claude-kit
```

(ADO 形式テストの場合は `git clone https://dev.azure.com/<org>/<proj>/_git/engineer-claude-kit ".claude-kit"`、ただし本検証では GitHub mirror で代替可)

## 検証項目 V1-V6

### V1: build-rules.ps1 の単独動作 (env-agnostic)

**目的**: `source/rules/` から `dist/.claude/rules/` への build が正常に完了するか

```powershell
cd $env:USERPROFILE\.claude-kit
pwsh -NoProfile -File scripts/build-rules.ps1 -DryRun
pwsh -NoProfile -File scripts/build-rules.ps1
```

**期待結果**:
- `dist/.claude/rules/commit-convention.md`
- `dist/.claude/rules/file-granularity.md`
- `dist/.claude/rules/security-mobile.md`

-> 3 ファイル生成、内容に `audience: [claude]` frontmatter を含むこと

**MAX 環境**: OK 実施可

### V2: apply-claude-kit.ps1 の -DryRun 動作 (env-agnostic)

**目的**: ファイル配置のシミュレーションが正常に走るか

```powershell
pwsh -NoProfile -File scripts/apply-claude-kit.ps1 -Global -DryRun
```

**期待結果**:
- 7 ファイル (CLAUDE.md + agents 6 種) + 3 skill = 計 10 ファイルのプレビュー
- 出力に `[dry-run]` プレフィックス
- 実ファイル書き込みなし

**MAX 環境**: OK 実施可

### V3: apply-claude-kit.ps1 の実 -Project mode 配置 (env-agnostic)

**目的**: mock project dir に実際に配置できるか、placeholder substitution が成功するか

```powershell
$mockDir = Join-Path $env:TEMP "eck-verification-$(Get-Date -Format yyyyMMddHHmmss)"
New-Item -ItemType Directory -Force -Path $mockDir | Out-Null
pwsh -NoProfile -File scripts/apply-claude-kit.ps1 -Project $mockDir
```

**期待結果**:
- `$mockDir/CLAUDE.md`
- `$mockDir/.claude/agents/{commit-msg,lint-helper,log-summary,review,architect,debug-analyze}.md` (6 種)
- `$mockDir/.claude/skills/{commit-helper,leak-check,propose-adr}/SKILL.md` (3 種)
- `$mockDir/.engineer-claude-kit-applied` (JSON marker)

**placeholder 検証**:

```powershell
Get-Content (Join-Path $mockDir ".claude" "agents" "commit-msg.md") | Select-String -Pattern "model:"
# 期待: model: "us.anthropic.claude-haiku-4-5-20251001-v1:0"

Get-ChildItem $mockDir -Recurse -Include *.md | Select-String -Pattern '\{\{role:'
# 期待: 出力空 (全 placeholder が substitution されている)
```

**MAX 環境**: OK 実施可。**注意**: substitution された model ID は Bedrock 形式のため、このままでは MAX で動作しない (V5 で adaptation する)。

### V4: bootstrap.ps1 の DryRun 動作 (env-agnostic)

**目的**: bootstrap が clone 検出 + apply-claude-kit invoke の経路を正しく辿るか

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 -DryRun -SkipProjectPrompt
```

**期待結果**:
- `[ok] kit structure validated`
- `[url] derived from git remote: <URL>` (= GitHub URL が取得される)
- `[dry-run] would set user env ENGINEER_CLAUDE_KIT_GIT_URL = <URL>`
- `apply-claude-kit.ps1 -Global -DryRun` が internal で呼び出される
- 計 10 ファイルの dry-run プレビューが出力
- `Bootstrap complete.`

**user 環境変数の永続化されないことを確認**:

```powershell
[Environment]::GetEnvironmentVariable("ENGINEER_CLAUDE_KIT_GIT_URL", "User")
# 期待: $null または既存値のまま (DryRun のため新規設定なし)
```

**MAX 環境**: OK 実施可

### V5: 実 Claude Code セッションでの動作テスト (MAX adaptation)

**目的**: 配置された `~/.claude/` (or mock dir) で実際に Claude が動作するか

#### V5a: Bedrock 想定での試行 (Bedrock credentials 不在 -> 失敗想定)

```powershell
cd $mockDir
claude  # or claude code
```

**期待結果 (Bedrock 想定のまま)**:
- `~/.claude/settings.json` に Bedrock model ID が書かれているため、Claude Code が Bedrock 接続を試行 -> 認証失敗 / model not found エラー

**MAX 環境**: NG 失敗想定 (正常な反応)

#### V5b: Anthropic API 形式に adapt して試行

`settings.json` 内の model ID を一時置換:

```powershell
$settingsPath = Join-Path $env:USERPROFILE ".claude" "settings.json"
$content = Get-Content -Raw $settingsPath
$content = $content -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
$content = $content -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
Set-Content -Path $settingsPath -Value $content -Encoding UTF8 -NoNewline

# agents 内の model ID も同様
Get-ChildItem (Join-Path $env:USERPROFILE ".claude" "agents") -Filter "*.md" | ForEach-Object {
    $c = Get-Content -Raw $_.FullName
    $c = $c -replace 'us\.anthropic\.claude-sonnet-4-5-20250929-v1:0', 'claude-sonnet-4-5-20250929'
    $c = $c -replace 'us\.anthropic\.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5-20251001'
    Set-Content -Path $_.FullName -Value $c -Encoding UTF8 -NoNewline
}
```

```powershell
cd $mockDir
claude
```

**期待結果**:
- Claude MAX 経由で Sonnet 4.5 / Haiku 4.5 が応答
- CLAUDE.md のルーティング指示が認識される (「コミットメッセージ作って」で commit-msg sub-agent が呼ばれる等)
- agents の各 sub-agent が機能する

**MAX 環境**: WARN 実施可だが、**Anthropic API 形式での Claude Code 動作は要実機検証**。MAX 契約での API access の仕様によって挙動が変わる可能性あり

**注意**: V5b で書き換えた settings.json / agents は、Bedrock 環境で再 apply する際に元に戻る (apply-claude-kit.ps1 が再 substitution するため)。テスト後の手動 revert は不要。

### V6: cost-observe-bedrock.ps1 (Bedrock 専用、MAX 環境 SKIP)

**目的**: AWS Cost Explorer 経由で Bedrock コストを取得

```powershell
pwsh -NoProfile -File scripts/cost-observe-bedrock.ps1 -DryRun
```

**期待結果 (Bedrock 環境想定)**:
- `aws ce get-cost-and-usage` コマンドが組み立てられる
- 実行されず (DryRun のため)

**MAX 環境**: NG **SKIP** (AWS CLI 不在 + Bedrock アクセスなしのため、本検証の範囲外)

dry-run まで動作確認するだけでも以下が確認可能:
- スクリプトが ASCII only で書かれている
- 引数パースが正常に動く
- AWS CLI 不在時の warning メッセージが適切

## 検証結果記録

各 V1-V6 の結果を本書の末尾に追記する形式:

```
## 実施結果

### 実施日: YYYY-MM-DD
### 実施環境: Windows 11 + Claude MAX 20x

#### V1 (build-rules.ps1)
- [PASS/FAIL]: 詳細...
- 生成ファイル数: 3

#### V2 (apply-claude-kit -DryRun)
- [PASS/FAIL]: 詳細...

(以下 V3-V6 同様)

### 全体判定
- MAX 環境で実施可能な範囲 (V1-V4 + V5b) は [全て PASS / 部分 FAIL: <内容>]
- Bedrock 専用 (V5a + V6) は SKIP
- 次のアクション: <Phase 4 着手 / 不具合修正 / etc>
```

## 注意事項

- V3 で配置された mock dir は検証完了後に削除推奨: `Remove-Item -Recurse -Force $mockDir`
- V5b で `~/.claude/` を直接書き換える場合は、事前準備 A のバックアップを必ず実施
- 本検証は **本番運用前の Phase 1-3 健全性確認**。MAX 環境で完走できれば、Phase 4 の追加実装着手判断 OK
- Bedrock 環境での完全動作は別途 (実 Bedrock 環境利用可能になった時) 検証する

## 関連

- ADR-0001 (clean start design) §G モデル戦略
- ADR-0003 (bootstrap design) §A bootstrap フロー
- ADR-0004 (auto model routing) §B sub-agent 定義
- README §6 制約 (Windows + PowerShell ASCII only)

---

## Appendix A: 自宅 vs Bedrock 検証マトリクス

正式 release 前の暫定 doc。**ほとんどの機能は自宅 (Anthropic API 直 = 非 Bedrock) で先行検証可能**。Bedrock 環境必須は cost 計測 / 1h cache / Bedrock model ID 受理のみ。

### A. ファイル配布 / スクリプト系 (API 不要、純粋 PowerShell + Git)

| 項目 | 検証方法 | 期待結果 |
|---|---|---|
| `install-deps.ps1` | `pwsh scripts/install-deps.ps1 -DryRun` で確認後、`-DryRun` を外して実行 | winget 経由で gitleaks / gh / pwsh / node がインストール (既存は skip) |
| `scripts/lint.ps1 -Strict` | `pwsh scripts/lint.ps1 -Strict` (PSScriptAnalyzer 自動 install) | PS 5.1 互換性違反があれば exit 1 |
| `bootstrap.ps1` clone + 配置 | `git clone … ~/.claude-kit` → `./bootstrap.ps1` | `~/.claude/` 配下に CLAUDE.md / settings.json / agents / skills / commands / work-schedule.yaml が出現 |
| `apply-claude-kit.ps1 -Global -DryRun` | コマンド実行 | dry-run 出力で 12+ ファイルの配置先表示 |
| `apply-claude-kit.ps1 -Project <path>` | mock project 作成 → 実行 | project 配下に CLAUDE.md / .claude/rules / hooks / .gitleaks.toml / .mailmap / .gitignore 配置 |
| `build-rules.ps1` source → dist 変換 | `pwsh scripts/build-rules.ps1` | `dist/.claude/rules/*.md` 5 件生成 |
| Pester smoke test 全 23 件 | `Invoke-Pester tests/apply-claude-kit.tests.ps1` | 全 pass |
| `.work-end-today` 自動配布 | apply Global 実行 → `~/.claude/work-schedule.yaml` 確認 | 初回 hint 表示 + yaml 配置 |

### B. Slash Command / Skill / Agent 系 (Anthropic API 直で動作可)

**事前準備**: `~/.claude/settings.json` を Anthropic API 用に一時編集する:

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "<your home API key>",
    "ANTHROPIC_MODEL": "claude-sonnet-4-5-20250929",
    "ANTHROPIC_SMALL_FAST_MODEL": "claude-haiku-4-5-20251001"
  }
}
```

- model ID から `us.anthropic.` prefix を外す
- `CLAUDE_CODE_USE_BEDROCK=1` 削除
- `ENABLE_PROMPT_CACHING_1H_BEDROCK=1` 削除 (Anthropic API 直では効果なし)

| 項目 | 検証方法 | 期待結果 |
|---|---|---|
| `/apply` slash command | Claude Code で `/apply` 入力 | apply-claude-kit.ps1 が起動、配布実行 |
| `/checkpoint` (Group B) | Claude Code で `/checkpoint` | `.claude/checkpoints/<YYYYMMDD-HHMMSS>-<slug>.md` 生成、要約は Haiku で実行 |
| `/resume` (Group B) | `/resume` または `/resume <slug>` | 最近 5 件提示 → 選択 → context 復元 |
| agents 6 種 (commit-msg / lint-helper / log-summary / review / architect / debug-analyze) | 各種タスク依頼 → 自動委譲 | sub-agent 起動、適切な model に routing |
| skills 3 種 (commit-helper / leak-check / propose-adr) | 関連トリガで起動確認 | skill 起動、期待動作 |
| **work-end-reminder rule** | 朝 1 番に Claude 起動 | 「今日は何時に仕事を終わりますか?」と質問 |
| **interactive 質問の回答 parse** | `17:30` / `休み` / `yaml` / `skip` 入力 | `~/.claude/.work-end-today` に書込、次ターンで動作確認 |
| 大タスク確認 (Case 2) | 終業 30 分前 + 「実装」キーワード prompt | 着手前に (a)/(b)/(c) 選択 |
| 終業時刻過ぎ reminder (Case 3) | 終業時刻過ぎ + 任意 prompt | 末尾に reminder + 「お疲れ様」 |

### C. Git Hook / Leak 検出系 (gitleaks インストール + bash 環境)

| 項目 | 検証方法 | 期待結果 |
|---|---|---|
| `pre-commit` hook | テスト project で `git commit` (PII or AWS key を含む) | hook 起動、commit reject |
| `pre-push` hook | `refs/backup/` への push 試行 | reject |
| `.gitleaks.toml` rule | `gitleaks protect --redact` 単独実行 | AWS / Anthropic key 検出 |
| `.mailmap` 配置 | 配置済 → `git log --use-mailmap` | identity normalization 動作 (本質的にはツール側機能、配置確認のみで十分) |
| `.gitignore` 配置 | 既存 vs 新規 project で確認 | 既存なら skip、新規なら配置 |

### D. Documentation / README

| 項目 | 検証方法 |
|---|---|
| README §2.1-§2.3 表 vs 実体 | 各行をリポジトリの実ファイルと突合 |
| ADR 0001-0006 | 全 ADR を順読、設計判断と実装の整合確認 |
| `docs/manual-verification/*.md` | 手順書を実行可能性で読む |

### Bedrock 必須 (自宅では検証不可)

| 項目 | 理由 | 必要環境 |
|---|---|---|
| settings.json の `CLAUDE_CODE_USE_BEDROCK=1` 経路 | Bedrock 接続そのもの | AWS IAM + Bedrock 有効 |
| Bedrock model ID 受理 (`us.anthropic.claude-sonnet-4-5-20250929-v1:0` 形式) | Bedrock 固有 ARN 形式 | Bedrock |
| `ENABLE_PROMPT_CACHING_1H_BEDROCK=1` の効果 (TTL 1h 効果検証) | Bedrock 固有 flag | Bedrock + 連続 call |
| `AWS_MAX_ATTEMPTS=2` の retry 抑制効果 | AWS SDK 動作 | Bedrock |
| `cost-observe-bedrock.ps1` | AWS Cost Explorer API | AWS 認証 |
| 本 doc §V6 (cost 計測) | cost-observe-bedrock 実行 | Bedrock |
| `docs/manual-verification/scenario-comparison.md` シナリオ A-D 完全実行 | Bedrock の応答 / cost / model routing 観測 | Bedrock |

### 推奨検証順序

1. **A 群 (ファイル配布)**: 自宅で完結、最小リスク、即実行可能
2. **B 群 (slash command / agent / rule)**: 自宅で大半完了、特に `work-end-reminder` と `interactive 質問` は実機検証必須
3. **C 群 (git hook)**: gitleaks インストール → 単独 project でテスト
4. **D 群 (docs)**: 自宅で読み合わせ可能
5. **Bedrock 環境で残り**: §V6 cost / 1h cache 効果 / Bedrock model ID 受理のみ

### Appendix の管理

本 appendix は **正式 release 前の一時情報**。release 後の doc 整理時に、本 bootstrap-installation.md 全体を refresh する流れで一緒に整理する (削除 or Quick Start に統合)。
