# Changelog

All notable changes to engineer-claude-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
