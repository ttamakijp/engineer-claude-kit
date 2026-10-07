# Mobile security リファレンス

OWASP Mobile Top 10 対応表と、security-mobile rule の根拠。

> この文書は `~/.claude/rules/security-mobile.md` から分離した**読み物**です
> (ADR-0015 §B-2)。rule 本文には検証可能な Do / Don't を残し、対応表と根拠はここに
> 置いています。Claude は必要なときにこのファイルを `Read` すれば足ります。
> `@import` では繋いでいません — import したファイルも launch 時にロードされるため、
> context 削減の効果がゼロになります (ADR-0015 事実 3)。

## OWASP Mobile Top 10 対応表

| 項目 | 対応 |
|------|------|
| M1 不適切な認証情報管理 | API キーの外部化、`BuildConfig` 経由のみ |
| M2 安全でないデータ保存 | `EncryptedSharedPreferences` / SQLCipher で機密データ保護 |
| M3 安全でない通信 | 全通信を HTTPS / TLS 1.2 以上に限定 |
| M5 不十分な暗号化 | AES-256-GCM 等の強固なアルゴリズムを使用 |
| M8 コード改ざん | ProGuard 難読化、整合性チェック |
| M9 リバースエンジニアリング | デバッグ情報の release 除外 |

## 根拠

- OWASP Mobile Top 10 は業界標準で、リスク優先順位の根拠になる
- 暗号化キーをコードに含めると静的解析で容易に抽出可能なため Keystore 必須
- supply chain 攻撃は 2020 年以降急増しており、依存の出所確認は基本動作
- Claude に `.env*` / `*.keystore` を読ませると、トークンが context / 学習データへ
  流出する経路になる

## リポジトリ段階での PII / クレデンシャル検出

ログ出力規約はランタイム挙動の話ですが、**リポジトリ commit / push 段階での PII 混入**
も同じカテゴリで防御します。「ログに出すな」「リポにコミットするな」の両層で守る、が
覚えるべき形です。

本キットでの実装は以下が担っています:

- `leak-check` skill — ad-hoc / pre-commit 想定の PII・credential 検出
- `templates/git-hooks/pre-commit` — メールアドレス / 電話番号 / API キー形式の検出
- `templates/git-hooks/pre-push` — host allowlist と backup ref の拒否
- `.gitleaks.toml` — gitleaks ルール
- GitHub push protection + CI の Leak Scan ジョブ

検出したい対象:

- 個人メール (noreply 以外)
- 電話番号 (日本携帯 070/080/090 / +81 / +1 北米)
- 住所 (〒NNN-NNNN / US street address)
- 社内ドメイン (`*.co.jp` / `*.atlassian.net` 等)
- クレデンシャルファイル (`.env` / `*.pem` / `*.key` / `local.properties` / `*.keystore`
  が tracked 化された場合)

> 以前の rule 本文には `scripts/check-leakage.ps1` を「Phase 2 以降で実装予定: TBD」
> として参照する節がありましたが、そのスクリプトは作られず、実際の防御は上記の
> leak-check skill + git hooks + gitleaks + CI に落ち着いています。存在しない
> ファイルを指す記述だったため、ADR-0015 §B-2 の整理で削除し、ここに事実ベースで
> 書き直しました。
>
> PII 検出ポリシーそのものの ADR は未採番です (TBD)。

## 関連

- `~/.claude/rules/security-mobile.md` — Do / Don't (Kotlin / Swift / gradle 等を
  触るときにのみロードされる本文)
- ADR-0009 — leak protection governance
- ADR-0015 — 指示面の削減と、この分離の方針
