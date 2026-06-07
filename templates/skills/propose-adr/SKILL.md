---
name: propose-adr
description: |
  Architecture Decision Record (ADR) draft を起票する skill。
  architect sub-agent (Sonnet 4.5) で代替案 + 根拠を整理する。
---

# propose-adr

`docs/adr/drafts/proposed-<slug>.md` を新規作成し、ADR の構造化された draft を生成する。

## 起動条件

ユーザが以下のいずれかを依頼したとき:
- 「ADR 起票」「architectural decision」「設計判断を文書化」
- 大きな技術選択 (DB / framework / 認証方式 等) について議論し始めたとき
- 既存設計を覆す変更を提案するとき

## 実行手順

1. ユーザから以下の情報を取得:
   - **課題** (1-3 行): 何を決めたいか
   - **制約** (技術 / 期間 / 既存依存)
   - **関連 ADR / rule / コード** (もしあれば)
2. `docs/adr/` 配下の既存 ADR 番号を確認し、次の連番を決定
3. **Task tool** で `architect` sub-agent (Sonnet 4.5) を起動:
   - 課題 + 制約を渡す
   - 代替案 **最低 2 案** (利点 / 欠点併記) を生成させる
   - 推奨案 + 根拠を生成させる
4. sub-agent の返答をテンプレ化して `docs/adr/drafts/proposed-<slug>.md` に書き出す:

```markdown
# ADR-<NNNN>: <タイトル>

**ステータス**: Proposed
**日付**: <YYYY-MM-DD>

## コンテキスト
<課題 + 背景>

## 決定
<推奨案>

## 検討した代替案
### 代替案 1: <名称>
- 利点 / 欠点

### 代替案 2: <名称>
- 利点 / 欠点

## 未解決の問い
<最低 1 件>

## 結果
### 利点
### 欠点

## 参照
```

5. 生成ファイルパスを提示し、ユーザに review を依頼

## 制約

- ADR の **promote** (Proposed → Accepted) は skill では行わない (user 判断)
- 代替案は **最低 2 案** を強制。「推奨案 1 案のみ」になりがちな場合は再考を促す
- propose-adr workflow の不変原則 (代替案強制 / Proposed 起票) と整合
- 生成 ADR は `Proposed` ステータスで起票し、勝手に Accepted 化しない
