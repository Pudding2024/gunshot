# 開発・ビルド・テストガイド

Gunshot (GoToHP for iOS) のローカル開発環境構築、ビルド、テスト実行、およびパッケージ作成の手順です。

---

## 🛠️ 開発環境の要件

- **OS**: macOS（推奨）または Linux
  - ※ネイティブ Objective-C / Theos のビルドには macOS と Xcode Command Line Tools が必要です。
  - ※Go コアの単体テストは Linux や Windows でも実行可能です。
- **Go**: 1.22 以上（Go 1.26 推奨）
- **Python**: 3.10 以上
- **パッケージビルド用ツール**:
  - [Theos](https://theos.dev/)（環境変数 `$THEOS` の設定が必要）
  - `ldid`
  - `dpkg` (macOS の場合は `brew install dpkg`)

---

## 📥 リポジトリのクローン

サブモジュール（`GotohpCore/upstream` 等）を含めてクローンします。

```sh
git clone --recurse-submodules https://github.com/tqmane/gunshot.git
cd gunshot
```

---

## 🧪 テストと品質チェック

リポジトリ直下で以下のスクリプトを実行して検証します。CI (GitHub Actions) でも同様のチェックが行われます。

| コマンド | 内容 |
| :--- | :--- |
| `bash scripts/test-core.sh` | ローカライズ整合性、Go コアの単体テスト（race 検出付き）、C/Go ブリッジ結合テスト |
| `bash scripts/test-native.sh` | macOS 上でのネイティブ Objective-C テスト（引数に `jailed` または `jailbreak` を指定可能） |
| `python3 scripts/format.py --check` | コードフォーマット検証（Objective-C, Go, Python） |
| `python3 scripts/verify-package.py jailed` | 生成されたパッケージの構成検証（`rootless` / `rootful` も指定可能） |

### コードの自動整形

フォーマットを整えるには以下のコマンドを実行します：

```sh
python3 -m pip install clang-format==18.1.8 black==25.1.0
python3 scripts/format.py
```

---

## 📦 パッケージのビルド

Theos を使用して、各環境向けの `.deb` パッケージおよび `.dylib` をビルドします。

```sh
export THEOS="$HOME/theos"

# 非脱獄向け（Sideload / LiveContainer）
bash scripts/package.sh jailed

# 脱獄向け（Rootless）
bash scripts/package.sh rootless

# 脱獄向け（Rootful）
bash scripts/package.sh rootful
```

- **非脱獄向け成果物**: `packages/jailed/` に `gotohp-tweak-jailed.deb` と `GunshotJailed.dylib` が生成されます。`gotohp-tweak-jailed.deb` には公式 Cydia Substrate 0.9.7113 の arm64 ランタイム（`CydiaSubstrate.framework`）が自動で取得・同梱されます。
- **脱獄向け成果物**: `packages/` に `gotohp-tweak-rootless.deb` 等が生成されます。

---

## 🔄 アップストリーム (xob0t/gotohp) の同期

Gunshot は [xob0t/gotohp](https://github.com/xob0t/gotohp) をサブモジュールとして取り込み、iOS 向けのアダプターをオーバーレイして使用しています。

1. アップストリームの新しいコミットを取り込む：
   ```sh
   bash scripts/sync-upstream.sh <commit_hash>
   ```
2. `GotohpCore/overlay/backend/` の iOS 独自実装との整合性を確認し、`bash scripts/test-core.sh` でテストが通ることを確認します。
3. 問題がなければコミットします。

---

## 🚀 リリースと GitHub Actions

- Git タグ（例: `v1.0.0`）をプッシュすると、GitHub Actions のビルドワークフローが自動実行され、全 3 種類のパッケージが Release に添付されます。
- 既存のリリースタグでビルドをやり直す場合は、GitHub Actions の **「Build and test」→「Run workflow」** から `release_tag` にタグ名を入力して実行できます。
