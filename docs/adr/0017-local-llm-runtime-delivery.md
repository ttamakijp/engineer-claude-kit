---
status: Proposed
date: 2026-11-04
deciders: [Tetsuya]
tags: [delegation, local-llm, deployment, apply, runtime]
---

# ADR-0017: local-llm 委譲を runtime (`~/.claude/`) へ届ける

**ステータス**: Proposed
**日付**: 2026-11-04
**Phase**: 6 (運用品質)

## コンテキスト

ADR-0016 で委譲先を local-llm MCP へ向け直し、PR #101/#102 で CLAUDE.md §3 と
config と prompt を揃えた。しかし snapshot 4 (2026-10-28〜11-03) の実測は
**Local call = 0 / Health probe = 0**。cost は $804 → $1,930 (per-turn +28%)。

2026-11-04 の実機確認で、**repo は正しいが runtime に届いていない**ことが判明した。

| 期待 | 実機 |
|---|---|
| 委譲の発火条件が常時ロードされる | **rule が存在しない** |
| config が runtime から読める | `~/.claude/config/` が**不在** |
| §3 が指す path が安定している | `~/.claude-kit/` = **dev checkout への symlink** |

原因は 3 つあり、どれも単独で委譲をゼロにする。

### 原因 1: 配布経路が無い

`apply-claude-kit.ps1` は `templates/` 配下 (CLAUDE.md / agents / skills /
commands)、dist の rule、root config、`work-schedule.yaml` を配布する。
`config/local-llm-delegation.yaml` はこのどれでもなく、**配布対象に入っていない**。
PR #102 は prompt を「kit 側から読めばよい」として意図的に非配布としたが、
その前提 (§3 が kit checkout を指す) 自体が原因 2 で崩れている。

### 原因 2: §3 が kit checkout を指していた

§3 は `~/.claude-kit/config/local-llm-delegation.yaml` を参照していた。これは
kit の install 先という**慣習**であって保証ではなく、開発機では working
checkout への symlink である。つまり **checkout の branch を切り替えると
session が従う指示が変わる**。runtime の指示が git の作業状態に依存する構造は、
kit の他の成果物 (最後に apply した内容が効く) と整合しない。

### 原因 3: 判定基準はあるが発火条件が無い

§3 は「大きな入力を context に載せずに済むなら委譲する」という**基準**を書き、
宛先は config を読めと書く。しかし

- どの場面が該当するかの列挙が常時ロードされる面に無い
- 一方で `~/.claude/agents/` には `commit-msg` / `log-summary` / `lint-helper`
  という Haiku 委譲先が配布済で、**description が毎 session の agent 一覧に載る**

結果、main agent にとって Haiku 委譲先は「黙って見える」のに local-llm は
「ファイルを読みに行かないと存在を知れない」。snapshot 4 の 0 件はこの非対称の
帰結と考えるのが自然である (snapshot 4 の窓は #101 merge 前を大半含むため、
0 件の全部を本原因に帰することはできない。切り分けは snapshot 5 で行う)。

## 決定

### A. 配布後の目標形を定義する

`apply-claude-kit.ps1 -Global` 後、以下が存在することを「配布済」と定義する。

| path | 内容 |
|---|---|
| `~/.claude/config/local-llm-delegation.yaml` | 宛先定義 (配布版) |
| `~/.claude/config/local-llm/<name>.md` | 各 tool の system prompt |
| `~/.claude/rules/local-llm-delegation.md` | 発火条件 (無条件ロード) |
| `~/.claude/CLAUDE.md` §3 | 判定基準 + 上記 config への参照 |

`~/.claude/rules/local-llm-fallback.md` は **含めない**。ADR-0016 決定 C 注記 3 の
配布保留を継続する (local-llm の失敗が 1 件も観測されていない)。

### B. `system_prompt_ref` を yaml からの相対パスにする

prompt 本体を `templates/local-llm/` から **`config/local-llm/`** へ移し、
`system_prompt_ref` を `local-llm/<name>.md` とする。参照の基準は
**yaml があるディレクトリ**と定義する。これで repo (`config/`) と配布後
(`~/.claude/config/`) の両方で同じ 1 行が解決し、配布時に内容を書き換える必要が
無くなる。配布時の内容書き換えは drift の原因になるため採らない。

### C. 発火条件を rule として配布する

`source/rules/common/local-llm-delegation.md` (`audience: [claude]`、`paths`
なし = 無条件) を新設する。§3 と重複する内容 (コスト実測値 / path 宛先限定 /
迷ったら自分で / commit は自分で) は**書かない**。rule が持つのは §3 に無いもの
だけ、すなわち **(1) 該当場面の列挙 (2) 出力を先にファイルへ落として path を
渡す手順 (3) config を 1 回読む**。1,271 B。

常時ロード面は 9,772 → 11,043 B (+13.0%) になる (実測。9,505 B は PR #101 で §3 が
4,187 B に増える前の値)。ADR-0015 の「足す前に測る」に
対しては、**§3 の指示が実測 0 件で発火していない**ことが測定済みの追加根拠である。
効果は snapshot 5 で判定する。

### D. 配布状態を検証する script を持つ

`scripts/check-kit-deployment.ps1` を新設し、**repo ではなく `~/.claude/` を**
検証する。本 ADR の原因 1-3 と PR #103 (dist に stale が残る) は、どちらも
「source は正しいが target が違う」形で、repo 内からは見えなかった。

## 検討した代替案

| 案 | 却下理由 |
|---|---|
| `~/.claude-kit/` 参照を維持し配布しない | 原因 2 が残る。runtime の挙動が checkout の branch 依存のまま |
| 両方の path を §3 に書く | 真実の源が 2 つになる。どちらが効いているか事後に判定できない |
| prompt を `~/.claude/skills/<name>/SKILL.md` として配布 | **有害**。これは 7B 向けの system prompt であり、Claude Code が自分の skill として読み込む |
| 発火条件を §3 に直接書き足す | byte 数は同等だが、ADR-0015 の rule 単位の発火計測から外れる |
| `audience` に `user` を追加 | 語彙は `claude` / `kit` の 2 値で、build filter は `claude` を見る。`user` は配布されない |

## 影響

- `templates/local-llm/` → `config/local-llm/` (git mv、参照 3 箇所を更新)
- `apply-claude-kit.ps1` は 500 行上限に達していたため、`work-schedule.yaml` の
  配布も含めて `scripts/lib/config-deploy.ps1` へ抽出した (488 行)
- Project mode は対象外。local-llm は machine の属性でありプロジェクトの属性でない

## 未解決の問い (Phase 2)

1. ~~**`~/.claude/agents/` の Haiku 委譲先 3 本をどうするか**~~ → **解決済 (Phase 2)**。
   `commit-msg` / `log-summary` / `lint-helper` を `templates/agents/` から削除し、
   orphan 削除を `rules/` から `agents/` へ一般化した (`scripts/lib/orphan-cleanup.ps1`)。
   agent file は不活性ではなく description が毎 session の agent 一覧に載るため、
   配布を止めるだけでは不足で、**配布済 copy の削除**まで必要だった (PR #103 と同型)。
   self-check は warning ではなく FAIL で判定する (apply で解消できる = gate として
   使える)。実測で agent 一覧から約 577 B/session が消え、常時ロード面は
   11,043 → 11,018 B
2. `log_summary` / `lint_fix` は `status: not_deployed` のまま。HX99G 側で
   `summarize_log` / `review_file` が deploy されるまで発火し得ない。Phase 1 の
   配布だけで発火が期待できるのは `commit_msg` のみ
3. snapshot 5 (apply 後 1 週間) で Local call > 0 を確認する。0 のままなら原因は
   配布ではなく発火条件そのものであり、未解決の問い 2 (宛先が未 deploy) が本命になる
4. **kit 管理外の agent 6 本** (`commit-writer` / `log-summarizer` / `code-reviewer` /
   `boilerplate-gen` / `checkpoint` / `resume`) が `~/.claude/agents/` に残る。
   marker の `applied_files` に無いため kit は削除せず報告のみ行う。うち
   `commit-writer` / `log-summarizer` の description は "MUST BE USED proactively"
   であり §3 と正面から矛盾する。削除は user の判断に委ねる

## 関連

- ADR-0016 (委譲先の選定)
- ADR-0015 (常時ロード面の削減と rule 発火計測)
- PR #103 (dist に stale が残る = 同型の target 側の不整合)
