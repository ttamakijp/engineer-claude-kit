---
id: local-llm-delegation
audience: [claude]
---

# local-llm への委譲

CLAUDE.md §3 の判定基準 (大きな入力を context に載せずに済むか) を、**発火する場面**
に落としたもの。宛先定義は `~/.claude/config/local-llm-delegation.yaml`。

## 要件

| 場面 | 定義 |
| --- | --- |
| 8,000 字超の build / test / lint 出力を要約する | `log_summary` |
| commit message を書く、かつ diff がまだ context に無い | `commit_msg` |
| 単一ファイルの typo / フォーマット / import の一次指摘 | `lint_fix` |

## Do

- 上記に当たったら **config を 1 回読む**。`enabled: true` かつ該当定義が
  `status: available` のときだけ委譲する
- 出力は先にファイルへ落とし (`tee` / リダイレクト)、**path を渡す**
- 委譲したことと結果を 1 行で報告する

## Don't

- 本文を読んでから渡さない。読んだ時点で締め出しが成立せず往復だけ増える
- `status: available` でない定義へ委譲しない (`fallback: self` に従う)
- `commit-msg` / `log-summary` / `lint-helper` sub-agent へ振り直さない

## 関連

ADR-0016 (宛先の選定)、ADR-0017 (runtime への配布)。
