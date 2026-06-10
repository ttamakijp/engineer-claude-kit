# Cost analysis (実測ベース)

本ドキュメントは engineer-claude-kit 適用時の cost reduction 効果を、
**実測 workload に対する Bedrock 3 構成 projection** で示します。

## 計測対象

- 計測日: 2026-06-10 (JST)
- scope: 89 JSONL / 44 session / 432 turn / 00:04-19:09 JST
- 実環境: native Anthropic API (Claude Opus 4.7 / 4.8 主力)
- pricing: Bedrock 概算 (公式値未確認、削減率は頑健、$ 絶対値は確定 pricing で比例スケール)

## Token 量実測

| 種別 | 量 |
|---|--:|
| cache_creation (cache_write) | 約 5.06M token (全て 1h TTL) |
| cache_read | 96.7M token (warm <5min: 90.9M / cold >5min: 5.81M) |
| input + output (cache 抜き) | Sonnet 換算 約 $0.94 相当 |

## Pricing (概算)

| | input | output | cache write 5m | cache write 1h | cache read |
|---|--:|--:|--:|--:|--:|
| Sonnet 4.5 / 4.6 | $3 / M | $15 / M | $3.75 / M | $6.00 / M | $0.30 / M |
| Haiku 4.5 | $1 / M | $5 / M | $1.25 / M | $2.00 / M | $0.10 / M |

cache modifier: write 5m = 1.25x base, write 1h = 2.0x base, read = 0.1x base.

## 3 構成比較 (本日 workload を Bedrock 上で処理した想定)

### 前提

- token 総量 (input / output / cache_create / cache_read) は不変
- cache hit behavior のみ pace に応じて変化:
  - **orchestration pace** (本日実測): turn 間隔 秒-分、cache_read の 94% が 5min 以内 warm hit
  - **human-pace** (典型 engineering): turn 間隔 5-15min、5m TTL では cache がほぼ切れる、1h TTL では gap < 60min で hit 継続

### Orchestration pace (本日実測ベース、子タスク並行)

| 構成 | cost | (1) 比 |
|---|--:|--:|
| (1) Bedrock デフォルト (Sonnet 4.6 + 5m TTL + Haiku) | $64.63 | 基準 |
| (2) Sonnet 4.5 + 1h TTL + Haiku | $60.31 | −6.7% |
| (3) (2) + engineer-claude-kit | $60.31 + α | −6.7% + α |

cache の 94% が warm hit のため 1h TTL の追加価値は限定的。

### Human-pace (典型 engineering、5-15min gap 前提)

| 構成 | cost | (1) 比 |
|---|--:|--:|
| (1) Bedrock デフォルト (Sonnet 4.6 + 5m TTL + Haiku) | $310.02 | 基準 |
| (2) Sonnet 4.5 + 1h TTL + Haiku | $60.31 | **−80.5%** |
| (3) (2) + engineer-claude-kit | $60.31 + α | **−80.5% + α** |

(1) は cache_read 96.7M が全て miss 化 → 96.7M × $3/M = $290 が input cost として上乗せされる。
(2) は 1h TTL により cache hit 継続、(1) との差が劇的に開く。

### 計算根拠 (主要項目)

**(1) Sonnet 4.6 + 5m TTL + human-pace**:
- base (Sonnet 4.6 + 1h TTL): $60.31
- cache_read 96.7M miss 化 (read → full input): 96.7M × ($3 - $0.30)/M = +$261.09
- cache_write 1h → 5m (2x → 1.25x): 5.06M × $2.25/M = −$11.38
- total: $310.02

**(2) Sonnet 4.5 + 1h TTL + human-pace**:
- 本日 cache pattern を Sonnet pricing でスケール (Opus run $301.55 ÷ 5)
- $60.31 (orchestration / human-pace でほぼ同等、gap >60min の小さい cold loss は無視)

## Kit 固有の経済的・非経済的価値

(2) と (3) の token cost が同水準なのは、cost 削減主因 (1h TTL + Haiku 委譲) が
Anthropic / Bedrock の設定機能だから。kit はそれを以下の形で補強する:

### 自動化価値

- ADR-0010 interactive settings wizard: 1h TTL + Haiku 委譲を 1 cmd で安全反映
- ADR-0007 hands-off: 既存 settings.json を絶対に上書きしない (欠落キー追加のみ)
- ADR-0013 kit self-update: `-Update` 1 cmd で kit + 設定の継続的最新化
- bootstrap.ps1: 新 PJ への展開を 1 cmd 化

### 構造的 cost 削減 (kit 固有)

- cleanup-orphan-processes skill (ADR-0011): stuck サブプロセスが context を消耗するのを自動回収
- statusLine 色分け (ADR-0012): context 使用率 90% で /compact を促し full re-upload を予防
- 質の高い skills / agents: 重複往復の削減 (定性的、定量化困難)

### 非経済的価値

- 5 層漏洩防御: pre-commit / CI gitleaks / leak scan / CODEOWNERS / branch protection
- CI 4 check 自動化: PSScriptAnalyzer + Pester (PS 5.1/7) + Leak Scan
- ADR 14 本による設計判断の永続化

## 注意・前提

- pricing は概算 (Bedrock 公式値未確認の前提)。削減率は頑健、$ 絶対値は確定 pricing で比例スケール
- human-pace の cache hit 率は「全 gap > 5min」の保守値 (worst case for default、best case for 1h TTL)
- 実 user の使い方で cost は (1) で $200-310、(2)/(3) で $60-90 のレンジ
- orchestration 中心の使い方 (本日 Tetsuya の実態) では kit 効果は −7% に縮小
- kit の真の経済的メリットは human-pace engineering 用途と新 PJ 展開コスト削減

## References

- ADR-0007: hands-off settings.json
- ADR-0010: interactive settings wizard
- ADR-0011: cleanup-orphan-processes skill
- ADR-0012: statusLine context usage visualization
- ADR-0013: kit self-update mechanism (-Update)
- 計測 source: 本リポジトリ root の `outputs/cost-analysis-2026-06-10.md` (local artifact)
