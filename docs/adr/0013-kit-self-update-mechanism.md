---
status: Accepted
date: 2026-06-10
deciders: [Tetsuya]
tags: [apply, bootstrap, self-update, git, ux]
---

# ADR-0013: kit self-update mechanism

> 本 ADR は G6b PR で起票され、同 PR で実装まで含めて Accepted とする。

## Context

kit を install 後、origin に新 commit が出てもユーザ手元の `~/.claude-kit/` は古いまま放置される。
その状態で `apply` を叩くと、古い skill / template がそのまま deploy され、ユーザは気付かないまま陳腐化した kit を使い続ける。

- kit は git clone 配布 (ADR-0003) なので、更新そのものは `git pull` で可能
- しかし「いつ pull するか」をユーザに委ねると、実際には誰も pull せず古いままになる
- 一方で `apply` のたびに勝手に pull すると、ネットワーク必須化・認証 prompt・ローカル編集の上書きといった副作用が出る (ADR-0007 hands-off の精神に反する)

## Decision

`apply-claude-kit.ps1` 起動時に kit 自身が origin に対して behind か検出し、ユーザに hint 表示する。
実際の更新は **明示的 opt-in (`-Update`)** のときだけ fast-forward pull で行う。

### 設計

- 起動時に `git fetch --quiet origin` を **timeout 5 秒**で実行 (background job 化し、hang してもそれ以上ブロックしない)
- fetch 失敗 / timeout / 非 git checkout はすべて **silent skip** (behind 判定不能 = `-1`)
- behind > 0 → warn 表示 (behind commit 数 + `-Update` hint)
- `-Update` → `git pull --ff-only` (divergent history では fast-forward 不能として loud に失敗 → conflict / merge commit を回避)
- `-UpdateForce` → `git reset --hard origin/<branch>` (escape hatch。ローカル編集を破棄)
- `-NoUpdateCheck` → fetch すら行わず検出を skip (CI / オフライン用)

実装は `scripts/lib/kit-updater.ps1` に `Test-KitBehind` / `Invoke-KitUpdate` として切り出す。
native `git` を直接 mock するのは PS 5.1 + Pester 3.4 では不安定なため、kit のテスト規約 (cleanup-processes.ps1 参照) に倣い、
git 呼び出しを scriptblock の injection point (`-FetchAction` / `-BranchResolver` / `-BehindCounter` / `-GitRunner`) で差し替え可能にし、テストを決定論化する。

`bootstrap.ps1` には `-Update` のみ伝播し、`apply -Global` subprocess に渡す。

### ADR-0007 (hands-off settings) との整合

ADR-0007 は user の **設定ファイル** (settings.json) を勝手に書き換えない原則。
本 ADR が更新するのは kit 自身 (`~/.claude-kit/` の git checkout) であり、user の設定とは無関係。
かつ明示承認 (`-Update` / `-UpdateForce`) なしには一切変更しない (検出と hint 表示のみ) ため、hands-off の精神を踏襲する。

## Alternatives considered

- (A) 完全 hands-off (現状維持): kit が古いまま気付かない → 却下
- (B) 自動 pull (毎回): ネットワーク必須・認証 prompt・上書きリスク → 却下
- (C) `-Update` opt-in (採用): user 意思を尊重しつつ 1 コマンドで最新化
- (D) 起動時 prompt 確認: hands-off と整合しにくく、非対話 / CI 経路を阻害 → 却下

## Refs

- ADR-0003 bootstrap and abstraction (git clone 配布)
- ADR-0007 hands-off settings.json
- ADR-0008 privilege-aware bootstrap
- ADR-0010 interactive settings wizard (opt-in pattern 参考)
- ADR-0011 cleanup orphan processes (injection-point テスト規約 参考)
