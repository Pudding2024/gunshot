# GoToHP for iOS (Gunshot)

[English](README.md) · [日本語](README.ja.md)

**Gunshot (GoToHP for iOS)** は、iOS 版 Google フォトアプリから Google Pixel に偽装して写真や動画をアップロードできる拡張機能（Tweak / 注入用ライブラリ）です。[xob0t/gotohp](https://github.com/xob0t/gotohp) の Go コアを iOS 向けに最適化して統合しています。

脱獄環境（Rootless / Rootful）および非脱獄環境（Sideloading / TrollStore / LiveContainer）の両方に対応しています。

---

## 🌟 主な機能

- **Pixel 偽装アップロード**:
  - **オリジナル画質（無制限）**: Pixel XL (Pixel 1) として偽装し、Google アカウントのストレージ容量を消費せずに原本画質でアップロード。
  - **保存容量の節約**: Pixel 2 として偽装し、節約画質でアップロード。
  - **アカウント容量を使用**: Pixel 8 として通常の容量を消費して原本画質でアップロード。
- **Google フォト純正バックアップの自動転送 (Native Backup Routing)**:
  - Google フォト標準のバックアップボタンや自動バックアップ操作を検知し、GoToHP のアップロードキューへ自動転送。
  - 普段どおり Google フォトを使うだけで Pixel 偽装アップロードが行われます。
- **アカウント連携の自動化**:
  - Google フォトにログインすると、連携アカウントを自動検出して OAuth トークンを取得。
  - 手動でのトークン取得や入力作業は不要です。
- **アルバム単位の一括インポート**:
  - iOS 標準ピッカーの枚数制限（1回100件）を気にせず、アルバムを指定して数千枚〜1万件超の写真や動画をまとめてキューに追加可能。
  - キュー上限は未完了ジョブのみに適用されるため、完了履歴を保持したまま大規模ライブラリを継続処理できます。
- **オリジナル画質の保持と Live Photo 対応**:
  - PhotoKit から追加の再エンコードを行わずに抽出。
  - 編集・ポートレート効果・カメラのトリミングを反映した現行のフルサイズ画像を優先。
  - RAW+JPEG は編集済みの JPEG/HEIC と元の RAW を両方アップロード（RAW 単独時は RAW を保持）。
  - **Live Photo** は対応する静止画と動画をペアリングし、Google フォト上で再生可能な状態で保存。
- **純正 UI への統合**:
  - プロフィールアイコン内に「GoToHP の設定」を追加。
  - プロフィール画面に Pixel 純正のような「無制限ストレージ」バナーを表示するオプションも搭載。
- **多言語対応**:
  - 日本語・英語に完全対応（簡体中文・ベトナム語カタログも内蔵）。

---

## 📱 スクリーンショット

<p>
  <img src="docs/images/unlimited-storage.png" width="240" alt="Google フォト プロフィールメニューの無制限ストレージ表示">
  <img src="docs/images/profile-menu.png" width="240" alt="プロフィールメニュー内の GoToHP 設定項目">
</p>
<p>
  <img src="docs/images/upload-settings.png" width="240" alt="アップロード設定（ログイン中アカウントと画質選択）">
  <img src="docs/images/backup-routing.png" width="240" alt="手動・自動バックアップの転送設定">
  <img src="docs/images/appearance-settings.png" width="240" alt="表示設定（言語切り替えと無制限ストレージ表示）">
</p>

---

## 📦 配布パッケージと動作環境

| 環境 | パッケージ | 動作方式 |
| :--- | :--- | :--- |
| **Jailbreak (Rootless)** | `gotohp-tweak-rootless.deb` | バックグラウンドデーモン (`gotohpd`) 経由でアップロード（アプリを閉じても継続） |
| **Jailbreak (Rootful)** | `gotohp-tweak-rootful.deb` | バックグラウンドデーモン (`gotohpd`) 経由でアップロード（アプリを閉じても継続） |
| **サイドロード / TrollStore / LiveContainer** | `gotohp-tweak-jailed.deb`<br>`GunshotJailed.dylib` | Google フォトアプリ内蔵で動作（アプリを前面で開いている間にアップロード） |

> [!TIP]
> パッケージは [Releases](https://github.com/tqmane/gunshot/releases) または [GitHub Actions](https://github.com/tqmane/gunshot/actions) のビルド成果物から入手できます。

---

## 🚀 インストール手順

### 1. サイドロード / TrollStore / LiveContainer（非脱獄）
詳しい手順は [Jailed 導入ガイド](docs/jailed.md) を参照してください。

- **Sideloadly の場合**:
  1. 復号（Decrypted）済みの Google フォト IPA を Sideloadly に読み込みます。
  2. **Advanced Options → Inject dylibs/frameworks** に `gotohp-tweak-jailed.deb` を追加します。
     ※deb に `CydiaSubstrate.framework` が同梱されているため、Sideloadly 側の **Cydia Substrate** は OFF にしてください。**Substitute** や **Sideload Spoofer** も通常は OFF にします。
  3. インストールを実行します。
- **TrollStore / 手動注入の場合**:
  - IPA に `gotohp-tweak-jailed.deb` を注入（Azule や Sideloadly の Export 機能など）し、TrollStore 等でインストールします。
- **LiveContainer の場合**:
  - `GunshotJailed.dylib` を LiveContainer の Tweaks フォルダに取り込んで適用します。

> [!IMPORTANT]
> **Google アカウントにログインする前に、Gunshot を注入・有効化してください。**
> GunshotJailed にはサイドロード時のログインエラーを防ぐ SSO 識別子・Keychain の自動補正機能が含まれています。
> ログインエラーが発生する場合の回避策については、[Jailed ガイドのトラブルシューティング](docs/jailed.md#issue-68-legacy-login-workaround) を参照してください。

### 2. 脱獄環境（Jailbreak）
1. お使いの脱獄環境（Dopamine / palera1n 等）に合わせて、`gotohp-tweak-rootless.deb` または `gotohp-tweak-rootful.deb` を Sileo などのパッケージマネージャーでインストールします。
2. 依存関係として **libSandy 1.1.6 以上**（[opa334's repo](https://opa334.github.io/)）が必要です。
3. もし Google フォト起動時にクラッシュする場合は、**Choicy** を使って Google フォトに対する Tweak 注入を Gunshot のみに絞り込んでください。

---

## 📖 使い方

1. **Google フォトを起動してログイン**
   - ログインが完了すると、自動的に GoToHP がアカウントを認識して接続します。
2. **画質や設定を確認**
   - 画面右上の **プロフィールアイコン → GoToHP の設定** を開きます。
   - アップロード画質（オリジナル / 保存容量の節約 / アカウント容量を使用）を選択します。
3. **写真・動画をアップロード**
   - **通常のバックアップと連携する場合**:
     - 設定内の **「手動・自動バックアップを GoToHP へ送る」** を ON にします（Google フォト本体のバックアップも有効にしてください）。
     - これで、Google フォトでバックアップを行うだけで自動的に GoToHP の Pixel 偽装キューに送られます。詳細は [バックアップ連携ガイド](docs/native-routing.md) をご覧ください。
   - **手動で選択してアップロードする場合**:
     - 設定内の **アップロード → 写真・動画を選択**（最大100件まで）。
     - 大量の写真を取り込む場合は **「アルバムを選択」** を使用すると、アルバム内の写真・動画を一括で取り込めます（詳細は [一括取込ガイド](docs/bulk-import.md)）。

> [!NOTE]
> - **サイドロード（非脱獄）版**: アプリが前面（フォアグラウンド）にある間のみアップロードが行われます。アップロード中は画面を開いたままにしてください。
> - **脱獄版**: 写真の取り込みが完了すれば、Google フォトを閉じてもバックグラウンドデーモンが送信を継続します。

---

## ⚙️ 画質プロファイル一覧

| 設定 | 偽装端末プロファイル | 動作 |
| :--- | :--- | :--- |
| **オリジナル** | Pixel XL (Pixel 1) | 原本画質でアップロード。Google ドライブ等のストレージ容量を消費しません。 |
| **保存容量の節約** | Pixel 2 | Google フォトの「保存容量の節約」画質でアップロード。容量無制限。 |
| **アカウントの保存容量** | Pixel 8 | 原本画質でアップロード。通常どおり Google ドライブの容量を消費します。 |

---

## 📚 ドキュメント

- [ドキュメント一覧 ポータル](docs/README.md)
- [サイドロード / LiveContainer 導入ガイド](docs/jailed.md)
- [Google フォト標準バックアップの転送設定](docs/native-routing.md)
- [アルバム一括インポート・トラブルシューティング](docs/bulk-import.md)
- [開発・ビルド・テスト手順](docs/development.md)
- [アーキテクチャ・設計解説](docs/architecture.md)
- [実機検証チェックリスト](docs/device-validation.md)
- [言語ローカライズの手順](docs/localization.md)
- [Google フォト解析資料インデックス](docs/analysis/index.md)

---

## 💬 コミュニティ

質問やサポート、情報交換は [Discord コミュニティ](https://discord.gg/zJBrCaf6dz) をご利用ください。

---

## ⚠️ 免責事項

本プロジェクトは Google および Apple とは一切関係のない非公式ツールです。**無保証・現状有姿 (AS IS)** で提供されます。
Google 側の仕様変更やアカウントポリシーの変更により、機能の停止、容量の計上、アカウントの制限等が発生するリスクがあります。大切な写真・動画の原本は必ず別の安全なストレージにもバックアップした上でご利用ください。Google フォトのバイナリや認証情報は一切配布していません。

---

## 📄 ライセンス

- **Gunshot**: [GNU General Public License v3.0 or later](LICENSE) (C) 2026 tqmane
- **同梱 gotohp コア**: [MIT License](GotohpCore/upstream/LICENSE) (C) 2024 xob0t
- その他サードパーティのライセンス表示は配布物内の `ThirdPartyNotices.txt` をご参照ください。
