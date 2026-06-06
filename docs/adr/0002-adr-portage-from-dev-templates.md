# ADR-0002: dev-templates ADR の移植精査

**ステータス**: Proposed
**日付**: 2026-06-05
**Phase**: 1 (foundation)
**関連**: ADR-0001 (clean start design)
**更新 (2026-06-06)**: 0017 cost-observation-kit を D 保留 → B 変形移植に格上げ (Phase 3.2 で Bedrock 縮小版を実装済)。

## コンテキスト

ADR-0001 で engineer-claude-kit の clean start 方針を確定した。次の課題は
dev-templates v3.5 の蓄積 ADR (実数 43 件: ADR-0001 + ADR-0003〜0044、ADR-0002 は
dev-templates 側で欠番) のうち、どれを engineer-claude-kit に持ち込むかを精査する
ことである。本 ADR で **完全移植 / 変形移植 / 破棄 / 保留** の 4 カテゴリで全 ADR を
分類し、Phase 2 以降の実装範囲を確定する。

判定はすべて ADR-0001 の決定 (§A リポ名 / §B ADO+bootstrap.ps1 / §C ハイブリッド
適用 / §D Claude only / §E engineer persona 固定 / §F Dispatch・scheduled-tasks
全削除 / §G Bedrock + Sonnet 4.5 main + Haiku 4.5 small fast / §G-2 Haiku 委譲 /
§H ADO 固定・GitHub 専用機能削除 / §I Windows PowerShell only) を根拠とする。

対象は番号付き ADR のみ。`docs/adr/drafts/` 配下の proposed-* は対象外。

> 注: ADR-0001 §C / §G-2 では「bootstrap・SessionStart hook の詳細は ADR-0002 で
> 確定」と記していたが、本 ADR-0002 は移植精査にスコープを再割当する。bootstrap /
> SessionStart hook の実装設計は後続 ADR (ADR-0003 想定) に分離する。

## 決定

dev-templates ADR は engineer-claude-kit 側で **新規採番** する。本 ADR の各表が
「dev-templates ADR → engineer-claude-kit での扱い」のマッピング table を兼ねる。
移植先 ADR 番号は実装着手時に採番するため、本表では移植先 Phase のみ示す。

### A. 完全移植 (7 件)

そのまま持ち込む不変原則 (Layer 1 骨格 / ADR 文化 / 安全原則)。実装は engineer-
claude-kit 流に書き直すが、決定の主旨は無改変。

| dev-templates ADR | title | 移植根拠 (ADR-0001) | 移植先 Phase |
|---|---|---|---|
| 0005 | 耐久 identifier を一次参照に使う | 普遍原則。CLAUDE.user.md の durable identifier 方針と整合 | Phase 1 |
| 0006 | PII / クレデンシャルファイル検出ポリシー | 安全原則。CLAUDE.md §6 (`.env*`/secrets/`*.keystore` 不読) と直結 | Phase 1 |
| 0008 | fail-safe / fool-proof 5 層防御 | ADR-0001「5 層防御の思想を Layer 1 骨格として継承」明記 | Phase 1 |
| 0020 | ADR review cadence / lifecycle | ADR-0001「ADR 文化を継承」。レビュー周期は不変原則 | Phase 1 |
| 0023 | propose-ADR workflow | ADR 文化の中核。CLAUDE.md §3「重要決定は ADR 記録」と整合 | Phase 1 |
| 0036 | skill backend neutrality (skill は LLM API を直呼びしない) | skill 設計の不変原則。§G Bedrock backend 前提で特に重要 | Phase 2 |
| 0038 | context discipline + minimal footprint | ADR-0001 の「context window 圧縮 / 機能過多排除」目標と直結 | Phase 1 |

### B. 変形移植 (19 件)

主旨は活かすが engineer-claude-kit の制約 (ADO / Windows / Bedrock / engineer 単一
persona / Dispatch なし / Claude only) に合わせて改変する。

| dev-templates ADR | title | 変形内容 | 移植先 Phase |
|---|---|---|---|
| 0004 | backup ref を local-only に限定 | apply-claude-kit.ps1 の backup 戦略に主旨を吸収 | Phase 2 |
| 0007 | apply orchestration | ADO/Windows/PowerShell 前提で apply-claude-kit.ps1 として再実装 (§B/§C) | Phase 2 |
| 0010 | 品質ゲート自動化 | GitHub Actions → azure-pipelines.yml に置換 (§H) | Phase 2 |
| 0011 | 依存管理自動化 | Dependabot 削除 (§H)、ADO 対応の依存更新方式に変形 | Phase 3 |
| 0012 | host-aware operation guard | `.git-host-allowlist` を ADO のみ allow に限定 (§H) | Phase 2 |
| 0013 | environment reproducibility kit | Windows / PowerShell 前提に限定して再構成 (§I) | Phase 3 |
| 0015 | onboarding + friendly errors + runbooks | 初心者導入要件の中核。bootstrap.ps1 に統合 (§B、ADR-0001 利点) | Phase 2 |
| 0017 | cost observation kit (週次観測) | 5 軸観測 (Claude API / GH Actions / cloud / PC リソース / runner uptime) collector+reporter+weekly cron+Issue alert を **Bedrock 1 軸のみ** に縮小し AWS Cost Explorer ベースで再実装 (§G)。weekly cron / Issue 自動起票は §F (scheduled-tasks 削除) のため省略し Phase 4 に繰延 | Phase 3.2 |
| 0024 | adoption tracking (marker / audit / discovery) | apply-claude-kit の deploy marker に主旨を吸収 (0042/0043 と統合) | Phase 2 |
| 0026 | 日本語ファースト文体規約 | engineer 向け 1 セットに圧縮 (§E)。カタカナ封印方針は維持 | Phase 1 |
| 0028 | defensive mailmap も漏洩面 / content-level PII 除去 | PII 方針 (0006) の一部として統合移植 | Phase 1 |
| 0029 | 三層アーキ (骨格 / persona / AI) | Layer 1 骨格は継承、persona 層 (engineer 固定) / AI 層 (Claude only) は単一化 (§D/§E) | Phase 1 |
| 0033 | rule applicability by project type | build-rules.ps1 は Claude 出力のみ (§D)、project_types filter は維持 | Phase 2 |
| 0037 | environment-aware backend profiles | multi-backend 検出を Bedrock profile 単独に特化 (§G) | Phase 2 |
| 0039 | cross-platform script parity + runtime 宣言 | PowerShell 単独で起票、sh parity は Phase 3 以降 (§I)。scheduled-task runtime 部分は破棄 (§F) | Phase 3 |
| 0040 | frictionless adopter bootstrap (curl/iex) | ADO + git clone + bootstrap.ps1 の β 方式に変形 (§B、ADR-0001 が参考実装と明記) | Phase 2 |
| 0042 | apply が sub-agent + small_fast_model settings を deploy | apply-claude-kit.ps1 が Haiku agent + settings.json を配布 (§C/§G-2) | Phase 2 |
| 0043 | deploy state visibility (marker/verify/freshness/SessionStart hook) | SessionStart hook を §C の CWD 検知・適用提案に活用、marker schema は簡素化 | Phase 2 |
| 0044 | Bedrock 環境検出 + model ID 自動解決 | Sonnet 4.5 / Haiku 4.5 の cross-region inference profile ID 解決に特化 (§G の前提技術) | Phase 2 |

### C. 破棄 (15 件)

engineer-claude-kit のスコープ外。各行に ADR-0001 のどの決定に基づく破棄かを示す。
既に dev-templates 側で Superseded/Deprecated 化されているものはその旨も付す。

| dev-templates ADR | title | 破棄理由 |
|---|---|---|
| 0001 | dev-templates v3.5 オリジナリティ roadmap | dev-templates 固有のロードマップ。engineer-claude-kit は ADR-0001 で独自方針確定済 (本 ADR-0001 が事実上 supersede) |
| 0003 | 多 AI 共通ルールソース + build pipeline | §D: Claude only。multi-AI 出力を削除 |
| 0009 | 成熟度 roadmap (8 Phase QCDSME+α) | dev-templates 固有の成熟度フレーム。engineer-claude-kit は独自 Phase 構成 |
| 0014 | session time budget + end-of-day hygiene | §F: scheduled-tasks 全削除。end-of-day hygiene の常駐基盤を持たない |
| 0016 | Windows PC を self-hosted runner 化 (private repo CI) | §H: GitHub Actions 削除。GitHub Free 枠制約は ADO では非該当 |
| 0018 | parallel task worktree isolation | §F: Dispatch 削除。並列 task 前提が消失 |
| 0021 | delivery predictability (release train) | 機能過多。初心者向けスコープ外 (ADR-0001 の機能過多排除方針) |
| 0022 | lead time DORA 4 metrics | 機能過多。初心者向けスコープ外 |
| 0025 | persona-driven multi-mode | §E: engineer persona 固定、multi-persona 全削除 (ADR-0001 で破棄を明記) |
| 0027 | manufacturing 業務テンプレ 5 種 | §E: manufacturing persona 削除 |
| 0030 | manufacturing sub-persona 15 種 | §E: manufacturing persona 削除 |
| 0031 | tool-only turn 禁止規約 (heartbeat) | §F: Dispatch 削除。orchestrator 不在で heartbeat 規約の前提が消失 |
| 0032 | 並列 task 上限 2 + sequential fallback (opus dispatch) | §F: Dispatch 削除 + §G: Opus 不採用 |
| 0035 | adopter vs dev-templates self の区別徹底 | dev-templates 固有の self/adopter 判定問題。leak-scan の安全部分は 0006/0028 に吸収済 |
| 0041 | distribution channel multiplexing (GitHub + ADO mirror) | §H: ADO 固定 (canonical 単一)。multiplex 不要 |

### D. 保留 (2 件)

判断材料不足。Phase 3 以降で再評価する。

> 0017 cost-observation-kit は当初本セクションに保留として分類していたが、Phase 3.2 で
> Bedrock 1 軸の縮小版を実装したため §B 変形移植に格上げした (上記参照)。

| dev-templates ADR | title | 保留理由 |
|---|---|---|
| 0019 | native technology by distribution target | 配布対象 project が未確定。engineer-claude-kit が扱う project 種別が固まってから技術選定指針を再評価 |
| 0034 | adopter upgrade mechanism (manifest + diff + 通知) | 再適用 (upgrade) は有用だが通知が scheduled-task 依存 (§F)。apply-claude-kit の再適用方式を Phase 2 で設計後に要否判定 |

## 検討した代替案

### 代替案 1: 全 ADR を完全移植

- メリット: ノウハウ完全継承、移植判断のコストゼロ、メンテ単純
- デメリット: ADR-0001 の初心者向け要件と矛盾 (機能過多)、不要 ADR が context を圧迫、
  Dispatch / multi-persona / GitHub 専用機能など実装不能な決定が混入

### 代替案 2: ADR は移植せず、必要時に dev-templates を都度参照

- メリット: 新リポは clean、参照は dev-templates の URL で十分
- デメリット: dev-templates 削除・改変リスクで参照が腐る、engineer-claude-kit の
  独立性が確立しない、判定根拠が文書化されず再現不能

## 未解決の問い

1. D 保留 2 件 (0019 native-tech / 0034 upgrade) の再評価タイミング —
   いずれも Phase 2 の apply-claude-kit 実装完了後が妥当か (0017 cost は Phase 3.2 で
   B 変形移植として実装済)
2. B 変形移植 19 件の移植先 ADR 番号採番方針 (1 ADR=1 番号 か、関連 ADR を統合採番か)
3. bootstrap / SessionStart hook の実装設計 ADR (ADR-0001 §C/§G-2 が ADR-0002 に
   委譲していた範囲) を後続 ADR に分離する件の番号確定
4. C 破棄のうち 0018 (worktree isolation) / 0031 (heartbeat) は Dispatch 文脈で
   破棄したが、solo 開発での worktree 活用余地を Phase 3 で再考するか
5. 0024/0042/0043 (deploy marker 系) の統合範囲 — 3 ADR を 1 つの deploy-state ADR に
   まとめるか個別に移植するか

## 結果

### 利点

- engineer-claude-kit の Phase 2 以降の実装範囲が A/B 26 件に明確化
- 初心者向け要件と整合 (破棄 15 件 = 不要機能の明示的排除)
- dev-templates のノウハウを「設計知見として」継承する範囲を文書で固定
- 各破棄判定が ADR-0001 §A-I の特定決定に紐付き、再現・検証可能
- 0017 cost-observation は Phase 3.2 で Bedrock 縮小版 (AWS Cost Explorer ベース) を
  実装完了し、D 保留 → B 変形移植に格上げ済

### 欠点

- 移植判断の確度は ADR-0001 + 当面のスコープ理解に依存し、Phase 3 で配布対象が
  広がると D 保留 / 一部 C 破棄の再評価が必要
- B 変形移植 19 件の具体内容は移植実装時に再度設計が必要 (本 ADR は範囲確定のみ)
- dev-templates 側の今後の新 ADR は本 ADR の精査対象外で、追従に別途トリアージが要る

## 参照

- ADR-0001: engineer-claude-kit clean start 設計 (§A-I)
- dev-templates ADR-0001 / ADR-0003〜0044 (https://github.com/ttamakijp/dev-templates/tree/main/docs/adr)
