# templates/local-llm/

local-llm MCP の各 tool に渡す prompt。`config/local-llm-delegation.yaml` の
`system_prompt_ref` がここを指す (kit 相対パス。絶対パスにしない)。

**apply は配布しない。** `apply-claude-kit.ps1` は `templates/` の各 subdir を明示列挙
して配布しており、本 dir はその列挙に入っていない。prompt は `~/.claude/` に置く必要が
なく、委譲時に kit 側 (`~/.claude-kit/templates/local-llm/`) から読めばよい。
配布対象を増やさない方針は PR #100 の `audience: [kit]` と同じ考え方。

## 一覧

| ファイル | target tool | 想定 model | status |
|---|---|---|---|
| `log-summary.md` | `local_llm__summarize_log` | `qwen2.5-coder:7b` | 未 deploy |
| `commit-message.md` | `local_llm__draft_commit_message` | `qwen2.5-coder:7b` | 未 deploy |
| `review-file.md` | `local_llm__review_file` | `qwen2.5-coder:7b` | 未 deploy |

status は `config/local-llm-delegation.yaml` が正。local-llm 側に tool が deploy
されたら config の `status` を `available` に変える (CLAUDE.md は触らない)。

Phase 1 model は `qwen2.5-coder:7b` (`hx99g-local-llm/config/ollama-models.yaml`、
`7b-instruct-q4_K_M` の alias)。Phase 2 は `qwen3-coder:30b`。

## 設計上の制約

- **kit は self-contained であること。** 本 kit は local-llm を持たない利用者にも
  配布される (ADR-0003)。template の存在自体が「local-llm を使え」という常時ロードの
  指示になってはいけない。宛先の切り替えは `config/local-llm-delegation.yaml` 側に
  寄せてあり (ADR-0016 未解決の問い 5)、`enabled: false` なら §3 は「自分で処理する」に
  帰着する
- **prompt も self-contained とすること。** main agent の context に依存しない
  (CLAUDE.md §4)。local-llm 側には会話履歴が無く、渡した path と引数しか見えない
- **出力形式を機械判定できる形にすること。** commit message は Conventional Commits の
  充足で判定でき (`CommitRate` が既にある)、品質を事後に測れる。log 要約の品質は
  機械判定できない (ADR-0016 未解決の問い 1)。各 template の `output_contract` と
  `output_sections` はこの判定可能性のために置いてある

## frontmatter

| キー | 用途 |
|---|---|
| `target_tool` | 対象 MCP tool 名 (prefix 無しの tool 名) |
| `audience` | `[local-llm]` 固定。`source/rules/` の `audience` とは別系統で、build-rules.ps1 の対象外 |
| `description` | 何をさせる prompt か |
| `model` | 想定 model。7B 前提で書いているので、変える場合は prompt も見直す |
| `delivery` | prompt の届け方 (下記) |
| `output_contract` | 出力節構成の識別子。kit 側は結果をこの構成で読む |
| `output_sections` | 出力の節数。骨格と一致することを test が確認する |
| `contract_markers` | 機械検証用の禁止事項 (`no-invention` 等) |

## delivery が 2 通りある理由

tool が **caller 側の system prompt を受ける param を持つか未確定**である。
実機で deploy 済の `chat` は `system` を受けるが、`summarize_log` /
`draft_commit_message` / `review_file` の param は local-llm 側で文書化されていない
(`docs/claude-code-integration.md` §2.3 は用途だけを定義している)。

- **param を持つ場合** — 本文をそのまま `system` に渡す
- **持たない場合 (server 内蔵 prompt)** — 本ファイルが server 側が実装すべき prompt の
  **仕様書**になる。どちらでも `output_contract` の節構成は守られる必要がある

deploy 時にどちらかを確定させ、この節を 1 つに縮めること。

## 使用例

`log_summary` を委譲する場合 (tool が deploy 済・`status: available` の前提):

```powershell
# 1. ログを file に落とす。本文は自分の context に載せない
powershell -NoProfile -File .\gradlew.ps1 test *> $env:TEMP\build.log

# 2. path を渡す。system は tool が param を持つ場合のみ
#    mcp__local-llm__local_llm__summarize_log  path=$env:TEMP\build.log
#
# 3. 返ってきた 4 節 (結果 / 失敗 / 原因の手がかり / 無視してよいもの) を読む
```

`commit_msg` は実機では `local_llm__generate_commit_message` (`diff_path` / `intent`)
が deploy 済で、`draft_commit_message` は未 deploy。`config` の `commit_msg` が現在
どちらを指しているかを見ること。

## 7B 前提で書いていること

`qwen2.5-coder:7b` は小さく量子化されたモデルなので、prompt は次の形に揃えてある。

- 指示は短く、箇条書き。長い散文の指示は劣化する
- **出力骨格を固定で与える** (見出しをそのまま出させる)。自由形式にすると崩れる
- 「書いてはいけないもの」を明示する。特に**推測で理由を書かせない**。
  diff や log に無い why をもっともらしく捏造するのが最も害のある失敗
- 日本語出力を指示しているが、識別子・エラー文は原文のまま引用させる。
  7B の日本語は英語より弱く、訳させると情報が落ちる

## 参照

- ADR-0016 (委譲先を local-llm MCP へ向け直す)
- `config/local-llm-delegation.yaml` (委譲先の定義。status が正)
- `source/rules/common/local-llm-fallback.md` (不達時の escalate。Phase 1 は配布保留)
- `docs/step-6-items/local-llm-implementation-plan.md` ((a)/(b)/(c)/(d) の設計)
- `tests/local-llm-delegation.tests.ps1` / `tests/local-llm-templates.tests.ps1`
  (config と template の契約を固定)
