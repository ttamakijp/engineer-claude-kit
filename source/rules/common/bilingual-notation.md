---
id: bilingual-notation
title: 英語混じり時の日本語併記
description: 英語表現を使う場合は初出時に日本語訳を併記し、読者の理解負荷を下げる
audience: [claude]
priority: medium
applyTo:
  default: "**/*.md"
tags: [language, documentation, clarity]
---

# 英語混じり時の日本語併記

## 要件

ドキュメント (markdown) およびユーザへの応答で英語表現を使う場合、初出時に必ず日本語訳を括弧で併記する。これにより、英語混じりを許容しつつ読者の理解負荷を下げる。

## Do (推奨)

- 英語表現を使う場合、初出時に日本語訳を併記する
- 例:
  - `audit (監査)`
  - `sweep (総ざらい)`
  - `dangling 参照 (未起票の参照)`
  - `preamble (前文)`
  - `scope (対象範囲)`
- 同一文書内の 2 回目以降は併記省略可
- 迷ったら併記する (過剰でも読者に親切)
- 訳語は文脈に応じて選ぶ (用語集は作らない、固定訳の強制はしない)

## Don't (禁止)

- 業界標準の純粋技術用語 (git / GitHub / README / JSON / YAML / ADR / Bedrock / Sonnet / Haiku 等) に併記しない
- 英語表現を併記なしで多用しない (読者の理解負荷が高まる)
- 文脈に合わない無理矢理な訳語を併記しない (むしろ理解を妨げる)

## 判断基準

| 表現 | 併記要否 | 例 |
|---|---|---|
| 日本語に置き換え可能な英語 | **必須** | `audit (監査)` `scope (対象範囲)` |
| 業界標準の技術固有名詞 | 不要 | `git` `JSON` `README` `Bedrock` |
| 略語 (ADR / API / CI 等) | 不要 (初出のみ展開推奨) | `ADR (Architecture Decision Record)` |
| 迷う場合 | 併記する | `dangling 参照 (未起票の参照)` |

## 適用範囲

- ユーザ向け応答 (Dispatch メッセージ / コード内のユーザ向けコメント)
- markdown ドキュメント (README / ADR / 検証手順書 等)
- コミットメッセージ本文 (subject の英語は Conventional Commits の要件、本文は本ルール適用)

## 適用外

- ASCII only 制約のある PowerShell スクリプト (英語のみ可、本ルール適用外)
- コードブロック内のコード / コマンド / 出力例
- 既存外部 API / プロトコル名 (例: `OAuth` `HTTPS`)

## 根拠

- 業務環境で Claude を使う初心者にとって、英語混じりの応答は理解負荷が高い
- 用語集 (glossary) を作るとメンテナンス負担が増え、文脈に応じた訳語選択ができなくなる
- 「初出時に併記、2 回目以降は省略」が最もバランスの良い負荷分散
- ADR-0001 §E の「engineer persona 固定」の延長として、業務環境向けの読みやすさを最優先する
