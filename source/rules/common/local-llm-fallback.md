---
id: local-llm-fallback
# audience に 'claude' を含めないので build-rules.ps1 はこの rule を dist へ出さず、
# apply も配布しない。**意図的な保留**であり壊れた設定ではない。
#
# 理由: local-llm の不達はまだ 1 件も観測されていない (実測は work 呼出 7 件 +
# health probe 2 件、失敗 0 件)。未観測の障害に常時ロードの指示を先回りで足すのは
# ADR-0015 の「足す前に測る」に反し、snapshot 4 の常時ロード面の測定も汚す。
# 内容は先に固めて repo に残し、配布だけ保留する (ADR-0016 決定 C の注記 3)。
#
# 配布へ切り替える条件: local-llm の失敗が 1 件でも観測されたら audience を
# [claude] に戻す (ADR-0016 未解決の問い 6)。そのとき paths は付けない
# (委譲の判断はファイル種別に依存しないため無条件ロードになる)。
audience: [kit]
---

# local-llm 不達時の escalate

## 要件

CLAUDE.md §3 の委譲先は local-llm MCP。**不達なら Haiku へ逃がさず、自分で処理する**。

| local-llm の状態 | 行動 |
|---|---|
| 応答あり | そのまま委譲する |
| 呼出が失敗 / timeout | 自分で処理し、**以降この session では委譲しない** |
| 出力が空 / 指示を無視 / 明らかに短い | 自分で引き取る。再試行は 1 回まで |

## Do

- 失敗は 1 行で報告する (「local-llm 不達のため自分で処理した」)。黙って切り替えない
- `health` は**委譲が必要になった時に 1 回だけ**叩く。session 冒頭の先回り確認や
  毎回の確認はしない (往復が増え、委譲で浮いた分を食い潰す)

## Don't

- 不達時に Haiku sub-agent へ振り直さない。CLAUDE.md §3 のとおり Haiku 委譲は
  自分で書くより高い
- 不達を理由に作業自体を止めない。委譲は手段で、成果物は自分の責任
- 可用性の確認と切り替えを user に判断させない。自分で完結させる

## 例外

commit / push / branch 操作は CLAUDE.md §3 のとおり**常に自分で実行する**。
local-llm が生成した commit message を使う場合も `git commit` を打つのは自分。

根拠: ADR-0016 決定 B (fallback を毎ターンの推論に委ねず `health` 基準の分岐にする)。
