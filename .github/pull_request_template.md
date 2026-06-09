<!--
PR タイトルは Conventional Commits (日本語) で記述してください。
例: docs(adr): 0001-0004 に status: Accepted を付与
詳細は CONTRIBUTING.md を参照。
-->

## 概要

<!-- 何を・なぜ変更したか (1〜3 行) -->

## 変更内容

<!-- 主な変更点を箇条書きで -->

-

## hard rules チェックリスト (CONTRIBUTING.md 準拠)

- [ ] `main` 直 push せず branch + PR 経由 (squash merge 前提)
- [ ] スクリプト変更は Windows PowerShell 5.1 互換 (ADR-0003 §C) ※docs/config のみなら N/A
- [ ] スクリプトは ASCII only / ファイルは UTF-8 (no BOM) (ADR-0003 §C, P6) ※同上
- [ ] secrets / API キーを含めていない (gitleaks + push protection)
- [ ] commit メッセージは Conventional Commits (日本語)

## テスト動作確認

<!-- 実行したコマンドと結果を記入。docs/config のみの変更で Pester/lint を skip した場合はその旨を明記。 -->

- [ ] Pester: `Import-Module Pester -RequiredVersion 3.4.0 -Force; Invoke-Pester -Path tests` (PS 5.1 / 7)
- [ ] lint: `powershell -NoProfile -File scripts/lint.ps1 -Strict`
- [ ] CI 4/4 緑 (Pester PS5.1 / Pester PS7 / PSScriptAnalyzer / Leak Scan)

結果:

```
（ここに実行結果を貼り付け、または「docs/config のみのため CI で確認」と記載）
```

## 関連 ADR

<!-- architecture-impacting な変更は ADR を起票し、ここにリンク。無い場合は「なし」。 -->

- ADR-xxxx: <!-- リンク or なし -->

## 補足

<!-- レビュアーへの注記、残課題、follow-up があれば -->
