# Contributing to engineer-claude-kit

## ワークフロー

1. branch を切る (`feat/...` / `fix/...` / `docs/...` / `chore/...`、`main` 直 push は不可)
2. 修正 → ローカルで Pester + lint を実行 (下記「テスト」参照)
3. PR を起票
4. CI 4/4 緑 (Pester PS5.1 / Pester PS7 / PSScriptAnalyzer / Leak Scan) を確認
5. squash merge + delete-branch

## hard rules

- `main` 直 push 禁止 (branch protection で強制、ADR-0009)
- 全変更は PR 経由 + squash merge (linear history を維持)
- スクリプトは Windows PowerShell 5.1 互換必須 (ADR-0003 §C)
- ファイルは UTF-8 (no BOM) 強制。書込/読込は `scripts/lib/encoding-helper.ps1` 経由 (ADR-0003 §C, P6)
- スクリプトは ASCII only (BOM 剥落事故防止、ADR-0003 §C)
- secrets / API キーを commit しない (gitleaks + GitHub push protection で多層防御)

## テスト

- Pester: `Invoke-Pester -Path tests` (PowerShell 5.1 / 7 両方で確認)
  - 注意: テスト suite は Pester 3.4 (legacy Should 構文) 前提。`Import-Module Pester -RequiredVersion 3.4.0 -Force` で固定してから実行する
- lint: `powershell -NoProfile -File scripts/lint.ps1 -Strict` (または `pwsh` で同等)
- leak scan (任意、ローカル): `gitleaks detect --source . --config .gitleaks.toml --redact -v`

## ADR

architecture-impacting な変更は ADR を起票する (`docs/adr/NNNN-<slug>.md`)。
ADR は YAML frontmatter (`status` / `date` / `deciders` / `tags`) を持ち、PR 内で review を受ける。
README の ADR Index にも 1 行追加すること。
