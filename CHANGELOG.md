# Changelog

All notable changes to engineer-claude-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **usage-insights 機能 (ADR-0014, G6f)** — Claude Code transcript
  (`~/.claude/projects/*.jsonl`) を解析し、model 効率 / cache 効率 (cold-read share) /
  token 浪費 score / stuck candidates / Haiku 委譲率 / cost trend を Markdown insights
  として `~/.claude/insights/` に蓄積。日次 (毎日 9:00) + 週次 (月曜 9:00) の
  scheduled-task が自動生成し、session 開始時に passive 提示 (未 ack 時のみ)。
  - `scripts/usage-insights.ps1` — 解析エンジン (`Get-InsightsScope` /
    `Get-UsageMetrics` / `Format-InsightsReport` / `Write-InsightsReport`、dot-source
    で関数 export、main は直接起動時のみ)
  - `scripts/pricing.psd1` — Bedrock 概算 pricing (web 確認待ち、相対比較専用)
  - `templates/skills/usage-insights/` — on-demand 入口 skill
  - `templates/commands/insights.md` — `/insights` slash command (--window / --ack 等)
  - `templates/scheduled-tasks/{daily,weekly}-usage-insights/` — 自動生成 trigger
  - `templates/CLAUDE.md` §9 — session 開始時の insights 確認 instruction
  - `apply-claude-kit.ps1` — 既定 ON で deploy、`-DisableInsights` で全 artifact skip
  - `docs/adr/0014-usage-insights.md` — 設計判断記録
  - `tests/usage-insights.tests.ps1` — Pester (mock JSONL ベース)
- README に「なぜ engineer-claude-kit が必要か」セクション + `docs/cost-analysis.md`
  を追加 (G6d): 実測 workload (432 turn / 44 session) を Bedrock 3 構成で projection し、
  cost 削減主因 (1h TTL + Haiku 委譲、−80%) が Anthropic / Bedrock の設定機能である点と、
  kit 固有の付加価値 (1 cmd 自動化 / hands-off / 構造的保護) を分離して説明。
- kit self-update mechanism (ADR-0013): `apply-claude-kit.ps1` が起動時に kit
  checkout 自身の behind を検出し hint を表示。`-Update` で fast-forward pull、
  `-UpdateForce` で hard-reset escape hatch、`-NoUpdateCheck` で検出 skip。
  `bootstrap.ps1` は `-Update` を `apply -Global` へ伝播。`/apply --update` で
  Claude Code からも起動可能。実装は `scripts/lib/kit-updater.ps1`
  (`Test-KitBehind` / `Invoke-KitUpdate`、injection-point ベースの Pester 19 件)。

### Changed

- **`scripts/usage-insights.ps1` (G6g)** — `Format-InsightsReport` に人間語併記を追加。
  技術メトリクスはそのまま残し、各 finding 直後に blockquote で対人類比を提示
  (Opus 偏重 / Haiku 委譲ゼロ / cache cold / token 浪費 / stuck / 反復依頼 / cost 増加)。
  日本語原文は `scripts/lib/plain-language-hints.json` に外出しし、ASCII-only の renderer
  `scripts/lib/plain-language.ps1` (`Get-PlainLanguageHint`) が `Read-Utf8NoBom` 経由で読む
  (PS 5.1 の BOM 無し `.ps1` mojibake を回避、encoding 単一系統を維持)。
- **`docs/adr/0014`** — 出力形式 (技術 + 人間語併記) と日本語原文外出しの設計判断を追記。
- **`scripts/usage-insights.ps1` (G6h)** — レポート生成時に kit-behind (ADR-0013
  `Test-KitBehind`) を検出し、origin より古い場合は冒頭に「kit 更新あり」セクションを追加
  (技術メトリクス + 人間語 blockquote 併記)。`kit-updater.ps1` 不在 (legacy install) /
  network 失敗時は silent skip。検出は `Invoke-UsageInsights` に置き、
  `Format-InsightsReport` は `-KitBehind` を受ける純関数として決定論を維持。banner 描画は
  `Format-KitBehindBanner` (`scripts/lib/plain-language.ps1`) へ抽出。
- **`scripts/lib/plain-language.ps1`** — `Get-PlainLanguageHint` に `-Metrics` placeholder
  置換を追加 (`{Behind}` 等)、`Format-KitBehindBanner` を新設。
- **`scripts/lib/plain-language-hints.json`** — `KitBehind` category 追加。
- **`docs/adr/0014`** — kit-behind 統合の設計判断を Decision に追記 (G6h)。
- **README.md** — クイックインストール callout を冒頭追加、「なぜ engineer-claude-kit が必要か」section を §0 の前へ移動 (新規訪問者が install command と Why に即到達する構造へ)。
- **`.mailmap`** — root 配置に集約 (Git 標準 convention、`git log --use-mailmap` /
  `git shortlog` 自動認識)。kit 自身の committer identity を正規化 (個人メアド commit
  を GitHub noreply identity へ集約、bot は `Claude <noreply@anthropic.com>` 統一)。
  配布テンプレート `templates/.mailmap` は別物として温存。
- GitHub Actions を Node24 対応版に更新: `actions/checkout@v4` -> `@v5`、
  `gitleaks/gitleaks-action@v2` -> `@v3` (2026-06-16 の runner Node24 強制切替に
  伴う deprecation 対応, #60)。

### Fixed

- **`apply-claude-kit.ps1`** — scheduled-task deploy が親ディレクトリ不在で失敗していた問題を修正 (G6i)。Write-Utf8NoBom 直前で New-Item で ensure。

## [0.1.0] - 2026-06-10

初版リリース。Phase 1-13 と Group 1-5 の全作業を統合した最初のタグ付きリリースです。
配布フロー (`bootstrap.ps1` -> `apply-claude-kit.ps1`)、Global / Project の 2 モード、
ADR-0001~0012 による設計決定、自己ガバナンス (CI / lint / leak dogfood) を含みます。

### Highlights

- **配布基盤**: `bootstrap.ps1` + `apply-claude-kit.ps1` による Global / Project
  両モードのテンプレート配布。プレースホルダ (`{{role:main}}` / `{{role:small-fast}}`)
  を `config/models.yaml` から解決。
- **ADR 確定 (0001-0012)**: model SSoT、bootstrap 抽象化、hands-off settings、
  privilege-aware bootstrap、checkpoint/resume、work-end-reminder、対話的
  settings wizard、孤立プロセス cleanup、context awareness を文書化。
- **対話的 settings wizard (ADR-0010)**: opt-in で `settings.json` の欠落キーのみを
  deep merge。変更前に必ず確認し、非対話環境では自動 skip。
- **自己ガバナンス**: branch protection + leak protection の dogfood
  (gitleaks / git hooks / `.mailmap`)、UTF-8 (no BOM) encoding hard rule、
  PowerShell 5.1 互換 hard rule (pwsh は opt-in)。
- **配布スキル 9 件 + コマンド 5 件**: apply / checkpoint / cleanup-processes /
  install-skill / resume コマンドと、commit-helper / leak-check / propose-adr /
  python-test / web-test / android-build / apply-claude-kit / skill-installer
  などのスキル。

### Added

- bootstrap + apply 配布フロー、Global / Project モード、models.yaml による
  モデル role 解決 (Phase 1-4)。
- project skill recommend パターン: project type 検出 + skill 推薦 (#35)。
- kit 自身の CI gate (PS 5.1 + 7 マトリクス Pester)、PSScriptAnalyzer lint、
  Azure DevOps テンプレート (#36)。
- 非対話環境向け PSScriptAnalyzer install 対応 (#39)。
- privilege-aware bootstrap: fail-fast な管理者検出 + 汎用 clone URL +
  実行権限ドキュメント (ADR-0008, #42)。
- UTF-8 (no BOM) encoding helper: Windows PowerShell の文字化けを READ 側で
  根本対処 (#44)。
- repository governance: branch protection + leak protection dogfood +
  CODEOWNERS (#47)。
- 対話的 settings wizard: opt-in deep merge (ADR-0010, #49)。
- 孤立 bash/gh/git subprocess の cleanup: safety filter + opt-in scheduled-task
  (ADR-0011, #50)。
- context awareness convention: statusline 色分け (緑/黄/赤) + CLAUDE.md /compact
  ガイドライン (ADR-0012, #51)。
- Project mode 配布 (git hooks / `.gitleaks.toml` / `.mailmap`) の Pester による
  byte 一致検証 (Group 5)。

### Changed

- `/apply` 中心の Quick Start 再構成 + skill / command の責務分離明記 (#45)。
- pwsh 専用前提を解消し PS 5.1 互換を hard rule 化 (install-deps は opt-in, #46)。
- config / model 解決を `lib/models-config.ps1` に抽出し apply を 508 -> 393 行に
  縮減 (file-granularity 遵守, #55)。
- README の鮮度落ち修正 + ASCII tree 整合 + overview diagram (#57)。
- ADR-0001~0004 の status を Accepted に整合化 (#56)。
- CI lint shell を PS 5.1 に統一 (pwsh spawn をやめ直接実行) + PR/Issue テンプレート
  追加 + oletools の §6.1 移管明示 (#58)。

### Fixed

- Pester の `Join-Path` を PS 5.1 互換形式に統一 (#34)。
- Pester ファイル直指定で `$PSScriptRoot` が空になる問題を解消 (#41)。
- install-deps の hint message で pwsh 依存を解消 (PS 5.1 でも実行可能と明示, #48)。
- statusline の inline `-Command` を `-File` script 化し Git Bash 経路の blank を
  解消 (#52)。

[Unreleased]: https://github.com/ttamakijp/engineer-claude-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ttamakijp/engineer-claude-kit/releases/tag/v0.1.0
