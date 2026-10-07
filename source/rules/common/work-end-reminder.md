---
id: work-end-reminder
audience: [claude]
# paths なし = 無条件ロード。時刻ベースの発火でファイル種別に依存しない。
---

# 終業時刻リマインダ

## 要件

statusline に `EOD <HH:MM>` が出ていたら、3 つ以上の tool 呼出を伴う作業 (実装 /
リファクタリング / 新規 PR / ADR 起票 等) の**着手前に**、今やるか翌セッションに
回すかを 1 行で確認する。

## Do / Don't

- `EOD` が出ていないときは何もしない (時刻を自分で調べない)
- 小さな依頼 (1-2 tool 呼出) では確認しない
- user が「今やる」と答えたら、その session 中は再確認しない
- 強制中断しない。判断は user に委ねる

## 例外

終業時刻の読み取り・marker file の読み書き・警告 window の判定はすべて
`statusline.ps1` が行う。Claude 側で marker file を書かない。

根拠と移管の経緯: ADR-0006、ADR-0015 §C
