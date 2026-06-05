# engineer-claude-kit

職場 (AWS Bedrock + Azure DevOps + Windows) で Claude を使い始めるエンジニア向け、
ワンコマンド bootstrap キット。

## Quick start

```powershell
# ADO repo から clone + bootstrap (PoC、bootstrap.ps1 は Phase 2 で実装)
git clone https://dev.azure.com/<org>/<proj>/_git/engineer-claude-kit `
  "$env:USERPROFILE\.claude-kit"
& "$env:USERPROFILE\.claude-kit\bootstrap.ps1"
```

## 設計判断

- **Persona**: engineer 固定 (選択 UI なし)
- **AI**: Claude のみ (Copilot/Cursor/Cline 出力なし)
- **モデル**: Bedrock 経由、main = Sonnet 4.5 (1h prompt cache 対応)、
  SMALL_FAST = Haiku 4.5。`ENABLE_PROMPT_CACHING_1H_BEDROCK=1` +
  `AWS_MAX_ATTEMPTS=2` を併用。Sonnet 4.6 は Bedrock 1h cache 非対応のため不採用
- **配布**: ADO repo + git clone + bootstrap.ps1
- **Dispatch / scheduled-tasks**: 採用しない

詳細: `docs/adr/0001-clean-start-design.md`
