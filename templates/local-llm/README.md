# templates/local-llm/

local-llm MCP へ渡す prompt template を置くディレクトリ。

**現状は placeholder で、中身は PR (b) で作る。** この README とディレクトリだけ先に
置いてあるのは、(c) で配布した `local-llm-fallback.md` が「委譲先は local-llm」と
書いており、その委譲の中身 (何をどう渡すか) の置き場所を決めておく必要があるため。

## 予定している内容 (PR (b))

| ファイル | 用途 |
|---|---|
| `commit-message.md` | staged diff から Conventional Commits 形式の subject を得る |
| `log-summary.md` | 8,000 字を超える build / test / lint 出力の要約 |

## 設計上の制約

- **self-contained であること。** 本 kit は local-llm を持たない利用者にも配布される
  (ADR-0003)。template の存在自体が「local-llm を使え」という常時ロードの指示に
  なってはいけない。実際の宛先切り替えは ADR-0016 未解決の問い 5 のとおり PR (a) で
  `config/` 側に寄せる
- **prompt は self-contained とすること。** main agent の context に依存しない
  (CLAUDE.md §4)。local-llm 側には会話履歴が無い
- **出力形式を機械判定できる形にすること。** commit message は Conventional Commits
  の充足で判定でき (`CommitRate` が既にある)、品質を事後に測れる。
  log 要約の品質は機械判定できない (ADR-0016 未解決の問い 1)

## 参照

- ADR-0016 (委譲先を local-llm MCP へ向け直す)
- `source/rules/common/local-llm-fallback.md` (不達時の escalate、PR (c))
- `docs/step-6-items/local-llm-implementation-plan.md` ((a)/(b)/(c)/(d) の設計)
