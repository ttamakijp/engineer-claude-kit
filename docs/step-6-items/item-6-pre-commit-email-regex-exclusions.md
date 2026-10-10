# Step 6 項目 6: pre-commit のメール正規表現に除外を付ける (draft)

**ステータス**: 提案のみ。実装着手は user の指示待ち。

## 背景

外部レビューの指摘:

> `.mailmap` と CODEOWNERS にメールアドレスがあるため、これらを編集した commit が
> 必ず止まる。対象パスから `.mailmap` / `CODEOWNERS` / `*.md` を除外、または
> noreply ドメイン許可リスト

## 現状

`templates/git-hooks/pre-commit` は staged diff の追加行すべてを 1 本の正規表現で
走査する。パス単位の除外はない。

```bash
staged_added="$(git diff --cached --no-color --unified=0 | grep '^+' | grep -v '^+++' | sed 's/^+//' || true)"
if printf '%s\n' "$staged_added" | grep -Eiq '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'; then
    echo "[pre-commit] possible email address in staged changes." >&2
    fail=1
fi
```

### 検証結果

`templates/.mailmap` を staged して実際に走査対象を取り出すと **4 件ヒット**する。

```
proper@email.com
commit@email.com
t_tamaki@icloud.com
t.tamaki@example.com
```

うち 3 件はコメント行の記入例 (`# Format:` / `# Example:`) である。正規表現は
コメントを区別しないため、`.mailmap` を編集する commit は **確実に止まる**。
指摘は `.mailmap` について正しい。

### ただし CODEOWNERS は該当しない

`.github/CODEOWNERS` の全文:

```
# Single-admin repository. ttamakijp owns all changes.
# See ADR-0009 (repository governance) and CONTRIBUTING.md.
* @ttamakijp
```

**メールアドレスは含まれていない** (GitHub の `@username` 記法のみ)。本リポジトリの
CODEOWNERS を編集しても email チェックは発火しません。指摘の前提はこのファイルに
ついては成り立ちません。ただし CODEOWNERS 仕様はメール表記も許すため、将来書き換え
られたときに備える意味はあります。

### `*.md` は除外すべきか

README / ADR / docs にメールアドレスが載る可能性は現実にあります。本リポジトリで
実際に `*.md` が止まる例は現状ありませんが、`Co-Authored-By: ... <noreply@anthropic.com>`
のような行を docs に引用した時点で止まります。

## 提案

### A. noreply / example ドメインの許可リスト (推奨)

パスではなく**値**で判定します。誤検出の原因は「記入例として置かれた無害な
アドレス」なので、無害なドメインを許可するのが最も素直です。

```diff
-    if printf '%s\n' "$staged_added" | grep -Eiq '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'; then
+    # Allowlist by VALUE, not by path: placeholder and no-reply addresses are not
+    # PII, and dropping them keeps a real address in .mailmap or a doc detectable.
+    email_candidates="$(printf '%s\n' "$staged_added" \
+        | grep -Eio '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' \
+        | grep -Eiv '@(example\.(com|org|net)|email\.com|[a-z0-9.-]*\.invalid|[a-z0-9.-]*\.test|localhost)$' \
+        | grep -Eiv '^noreply@|@noreply\.' || true)"
+    if [ -n "$email_candidates" ]; then
         echo "[pre-commit] possible email address in staged changes." >&2
+        printf '%s\n' "$email_candidates" | sort -u | sed 's/^/           /' >&2
         fail=1
     fi
```

副産物として **どのアドレスで止まったかを表示できます**。現状は
「possible email address in staged changes」だけで、該当行を自分で探す必要があります。

ただし本案単独では `.mailmap` の `t_tamaki@icloud.com` は **依然として止まります**
(実在アドレスのため)。これは正しい挙動とも言えますが運用上は邪魔なので、B と併用します。

### B. `.mailmap` の記入例を無害なドメインへ差し替える

```diff
-# Example:
-# Tetsuya <t_tamaki@icloud.com> Tetsuya Tamaki <t.tamaki@example.com>
+# Example:
+# Proper Name <proper@example.com> Commit Name <commit@example.com>
```

A の許可リストと組めば `.mailmap` は完全に通ります。かつ **配布テンプレートから
実在の個人アドレスが消える**という独立した利点があります (本 kit は public repository)。

これは除外ルールの追加ではなく **原因の除去**であり、A より優先度が高いと考えます。

### C. パス単位の除外

```bash
staged_added="$(git diff --cached --no-color --unified=0 \
    -- . ':(exclude).mailmap' ':(exclude).github/CODEOWNERS')"
```

レビューが挙げた案そのものです。実装は短いですが、**除外したパスでは本物の漏洩も
検出できなくなります**。`*.md` まで除外すると ADR や README に実在アドレスを書いても
通るため、防御としては後退します。

## trade-off

| 案 | 利点 | 欠点 |
|---|---|---|
| A (値の許可リスト) | 無害な値だけ通す。検出力を落とさない。止まった値を表示できる | 正規表現が長くなる。許可ドメインの網羅は不完全になりうる |
| B (記入例の差し替え) | 原因を消す。public repo から実在アドレスが消える副産物 | `.mailmap` の例が抽象的になる (実用上の影響はほぼない) |
| C (パス除外) | 実装が最短 | 除外パスの防御が完全に消える。`*.md` 除外は実質 opt-out |

**A + B を推奨し、C は採りません。** C は「誤検出を消す」目的に対して「検出を消す」
方法であり、pre-commit が守ろうとしているもの (public repo への PII 混入) を
そのまま手放すことになります。

A の許可リストに `@example.com` / `*.invalid` / `*.test` を入れるのは RFC 2606 /
RFC 6761 の予約ドメインに沿った選択で、恣意的な除外ではありません。

## 実装イメージ

1. **B を単独で先に入れる** — `templates/.mailmap` の記入例差し替え。scope は
   `docs:` ではなく `fix(security):` が妥当 (public repo から実在アドレスを除去)
2. A を次の PR で入れる (`templates/git-hooks/pre-commit`)
3. テストを追加する。現在 `tests/` に pre-commit hook の**挙動**テストは存在しない
   (`project-mode.tests.ps1` は配布ファイルのハッシュ一致のみ)。bash hook なので
   一時 repo で `git commit` を走らせる統合テストになる:
   - `@example.com` を含む追加行 → 通る
   - 実在風アドレス (`someone@company.co.jp`) → 止まる
   - 止まったアドレスが stderr に出る
   - `.mailmap` の配布版をそのまま commit → 通る (B + A の回帰)
4. 電話番号の正規表現にも同種の誤検出がありうる (日付や version 文字列)。本項目の
   範囲外だが同時に点検する価値がある

## 未解決の問い

1. 許可ドメインをどこまで入れるか。RFC 予約 (`example.*` / `*.invalid` / `*.test` /
   `localhost`) は安全。社内ドメイン (`*.co.jp` 等) は allow ではなく warn 止まりに
   すべき
2. 電話番号の正規表現は `2026-10-11` のような日付にマッチしないか (要検証)
3. hook は `git commit --no-verify` で素通りする。許可リストを整えるより
   「止まったら理由が分かる」ほうが運用価値が高い可能性がある (A の stderr 表示部分)

## 関連

- `templates/git-hooks/pre-commit` (email / phone / API key の 3 チェック)
- `templates/.mailmap` (記入例に実在アドレス)
- `.github/CODEOWNERS` (メールなし。指摘の前提は本 repo では不成立)
- `.gitleaks.toml` / CI の Leak Scan job (多層防御の他の層)
- ADR-0009 (leak protection governance)
