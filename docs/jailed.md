# 非脱獄（Jailed）導入ガイド — Sideloadly / TrollStore / LiveContainer

脱獄していない iOS 端末で Gunshot (GoToHP for iOS) を利用するための導入ガイドです。
Google フォトの IPA ファイルに Gunshot を組み込むことで、通常環境でも Pixel 偽装アップロードを利用できます。

---

## 📌 Jailed（非脱獄）版の特徴と動作仕様

- **アプリ内蔵で動作**:
  - 脱獄版のような常駐デーモンではなく、Google フォトアプリのプロセス内で動作する dylib（Go ランタイム内蔵）として組み込まれます。
- **フォアグラウンド実行**:
  - iOS のサンドボックス制限により、**Google フォトが画面上で開かれている間（フォアグラウンド）のみアップロードが進行します。**
  - アプリを閉じたり画面をロックすると処理は一時停止し、次回アプリを開いたときに自動的に再開されます。
- **ログイン補正機能を内蔵**:
  - サイドロード時に発生しやすい Google ログイン失敗や Keychain エラー（`-34018`）を回避するため、SSO 識別子と Keychain アクセスグループの自動補正機能を備えています。アプリのホスト初期化後にも再確認が行われます。

---

## 📦 必要なファイル

[Releases](https://github.com/tqmane/gunshot/releases) または [GitHub Actions](https://github.com/tqmane/gunshot/actions) のビルド成果物から以下のファイルを入手します。

| ファイル名 | 用途・同梱内容 |
| :--- | :--- |
| `gotohp-tweak-jailed.deb` | **Sideloadly / TrollStore / 手動注入用**。<br>Gunshot 本体、設定 plist に加え、インジェクター互換性のための公式 Cydia Substrate 0.9.7113（arm64 ランタイムおよび Info.plist のみ）を同梱。脱獄用のローダーやデーモンは含まれません。 |
| `GunshotJailed.dylib` | **LiveContainer 用**。<br>単体ライブラリ。Substrate へのリンクを持たないため、単体でそのまま読み込めます。 |

また、インストールには**復号（Decrypted）済みの Google フォト IPA** が必要です。

---

## 🚀 インストール手順

### 方法 1: Sideloadly を使用する場合 (推奨)

Windows または Mac の Sideloadly を使って IPA に注入・インストールします。

1. **Sideloadly を起動**し、iOS 端末を PC に接続します。
2. 左上の **IPA アイコン** に復号済み Google フォト IPA をドラッグ＆ドロップします。
3. **Advanced Options** を開きます。
4. **Inject dylibs/frameworks** にチェックを入れ、**「+」または「Add」ボタン**から `gotohp-tweak-jailed.deb` を選択します。
   *(※ダイアログに `.deb` が表示されない場合は、ファイル選択を「All Files (*.*)」に切り替えてください)*
5. **オプションの確認**:
   - `gotohp-tweak-jailed.deb` 内に `CydiaSubstrate.framework` が同梱されているため、Sideloadly 側の **Cydia Substrate** オプションは必ず **OFF** にしてください（同名フレームワークの二重注入を避けるため）。
   - **Substitute** および **Sideload Spoofer** も通常は **OFF** にしておきます。
6. 接続中の端末、Apple ID、および Bundle ID を確認し、**「Start」** をクリックして署名・インストールを実行します。

> [!TIP]
> **アプリを更新する場合**: 前回のインストール時と**同じ Apple ID・同じ Bundle ID** を指定して上書きインストールしてください。既存のログイン情報やアップロードキューが維持されます。

---

### 方法 2: TrollStore / 各種インジェクターツール

TrollStore 環境や Azule 等のツールを使用する場合の手順です。

1. 復号済み Google フォト IPA に、インジェクターツール（Azule や Sideloadly の Export 機能など）を使って `gotohp-tweak-jailed.deb` を注入します。
   - **手動でバイナリを配置する場合**:
     `GunshotJailed.dylib` をアプリ内の `Frameworks/` に配置し、メイン実行ファイル（`GooglePhotos`）に対して `@rpath/GunshotJailed.dylib` の `LC_LOAD_DYLIB` を追加してください。
     deb と同等の構成にする場合は、`CydiaSubstrate.framework` も `Frameworks/` にコピーして `@rpath/CydiaSubstrate.framework/CydiaSubstrate` を読み込ませ、framework を含む全バイナリを同一証明書で再署名してください。
2. 注入後の IPA を TrollStore 等で端末にインストールします。

---

### 方法 3: LiveContainer を使用する場合

JIT 不要でマルチアプリを実行できる LiveContainer で利用する手順です。

1. LiveContainer に復号済みの Google フォト IPA をインストールします。
2. **初回起動する前に**、LiveContainer の **Tweaks** タブを開きます。
3. Google フォト用のフォルダを作成し、その中に `GunshotJailed.dylib` をインポート（**Import Tweak**）します。
4. LiveContainer のアプリ設定から、Google フォトの **Tweak Folder** に作成したフォルダを指定し、**TweakLoader** を有効化します。
5. 必要に応じて署名（Sign）を行い、Google フォトを起動します。

---

## 🔑 初回起動とログインの流れ

> [!IMPORTANT]
> **Google アカウントにログインする前に、Gunshot を注入・有効化してください。**

1. インストールした Google フォトを起動します。
2. Google アカウントでログインします。
   - Gunshot がアプリの認証情報を自動検知し、GoToHP と連携します（手動でのトークン取得・入力は不要です）。
3. 画面右上の **プロフィールアイコン** をタップし、メニュー内に **「GoToHP の設定」** が表示されていることを確認します。
4. 設定画面を開き、お好みの画質プロファイル（Pixel XL オリジナル画質など）を選択してください。

---

## 💡 日常の使い方と注意点

- **アップロードの実行**:
  - 写真・動画のアップロードは、Google フォトが画面上でアクティブ（フォアグラウンド）になっている間に行われます。
  - 大量にバックアップする際は、端末の自動ロック（スリープ）を一時的にオフにするか、充電器に接続して画面を表示したままにしておくことをおすすめします。
- **純正バックアップの自動転送**:
  - 「GoToHP の設定」で **「手動・自動バックアップを GoToHP へ送る」** を ON にしておけば、Google フォト本来のバックアップ操作を通じて自動的に Pixel 偽装アップロードが行われます（詳細は [バックアップ転送ガイド](native-routing.md) を参照）。
- **中断と再開**:
  - アップロード中にアプリを閉じても、未完了のデータはキューに安全に保存されます。次回アプリを開いた際に自動で再開されます。

---

## ❓ トラブルシューティング

<a id="issue-68-legacy-login-workaround"></a>
### Google アカウントにログインできない場合（Issue #68 の回避策）

[Issue #68](https://github.com/tqmane/gunshot/issues/68) では、一部の環境（Google フォト 7.20.2 / iOS 27.0.1 / 無料 Apple ID 等）において、以下の二段階の導入手順による回避例が報告されています。

1. **初回ログイン時の一時的な構成**:
   - Gunshot と Cydia Substrate に加え、**Substitute** と **Sideload Spoofer** を一時的に有効にしてインストールし、Google アカウントにログインします（Sideloadly を利用する場合、deb 側に Cydia Substrate が同梱されているため、Sideloadly 側の Cydia Substrate オプションは OFF のままにします）。
2. **通常構成への入れ替え**:
   - ログイン成功後、**同じ Apple ID・同じ Bundle ID** を維持したまま、**Gunshot + Cydia Substrate のみ（通常構成）** の IPA を上書きインストールします。
   - ※Substitute と Sideload Spoofer が残っていると、GoToHP の設定画面を開いた際にクラッシュする事例が報告されています。
   - ※アプリを削除（アンインストール）すると保存されたキューや設定が失われるため、削除せず上書きインストールを行ってください。

> [!NOTE]
> 現在の Gunshot は SSO 識別子補正および Keychain 補正を内蔵しており、ホスト初期化後にも再確認を行います。まずは通常の手順で導入をお試しいただき、どうしてもログインエラーが解消しない場合に上記の手順をご検討ください。なお、この回避策は特定の旧構成で報告されたものであり、すべての環境やバージョンでの動作を保証するものではありません。

### その他のトラブル

- **Google にログインできない / エラー画面が出る**:
  - Gunshot が正しく注入されているか確認してください。GunshotJailed が注入されていれば、サイドロード時の SSO 識別子エラーが自動補正されます。
  - すでに Gunshot なしでログインを試みて失敗していた場合は、一度アプリをアンインストールし、Gunshot 注入済み IPA を再インストールしてからログインをお試しください。
- **「GoToHP の設定」が表示されない**:
  - 注入がメイン実行ファイル（`GooglePhotos`）に対して行われているか確認してください。App Extension や別バイナリに注入しても動作しません。
- **アップロードが進まない**:
  - Google フォトがフォアグラウンド（画面上）にあるか確認してください。
  - 「GoToHP の設定」を開き、アカウントが正しく接続されているか確認してください。必要に応じて「再接続」をタップします。
