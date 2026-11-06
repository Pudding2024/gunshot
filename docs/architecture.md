# アーキテクチャ・設計解説 (Architecture)

Gunshot (GoToHP for iOS) のシステム構成、各コンポーネントの責務、データフロー、および耐障害性設計の解説です。

---

## 🏛️ システム概要

Gunshot は、iOS の Google フォトアプリ（Objective-C / Swift）と、Google Pixel 偽装アップロードを行う Go コアエンジンを橋渡しするアーキテクチャを採用しています。

動作モードによって 2 種類の実行形態を持ちます：

```
【脱獄環境 (Jailbreak)】
[Google フォト (Tweak.xm / Native / UI)]
       │ (Mach Message / XPC)
       ▼
[バックグラウンドデーモン gotohpd (Daemon/)]
       │ (C/Go ブリッジ)
       ▼
[Go コアエンジン (internal/service/)] ──(HTTPS)──▶ Google フォト サーバー

【非脱獄環境 (Jailed / Sideload)】
[Google フォト (Jailed/Hooks.m / Native / UI)]
       │ (Direct In-Process Call)
       ▼
[組み込みサービス (Jailed/EmbeddedService.m)]
       │ (C/Go ブリッジ)
       ▼
[Go コアエンジン (internal/service/)] ──(HTTPS)──▶ Google フォト サーバー
```

---

## 📁 ディレクトリ構造とコンポーネントの責務

| ディレクトリ | 主な役割 |
| :--- | :--- |
| `Tweak.xm` | 脱獄版のエントリーポイント。Logos によるフック定義とライフサイクル管理。 |
| `Jailed/` | 非脱獄（サイドロード）版のエントリーポイント（`Hooks.m`）およびアプリ内組み込みサービスブリッジ（`EmbeddedService.m`）。インジェクター互換性のため公式 Cydia Substrate 0.9.7113 の arm64 ランタイム（`CydiaSubstrate.framework`）を deb に同梱。単体 `GunshotJailed.dylib` は Substrate にリンクせず LiveContainer で動作。 |
| `UI/` | 設定パネル（`GSPanel`）、アルバムピッカー（`GSAlbumPicker`）、アカウントメニュー統合（`GSAccountMenu`）、外観オプション。 |
| `Native/` | Google フォト内部機能との連携。アカウント検出・SSO トークン取得（`GSNativeAccount`）、標準バックアップ転送（`GSNativeRouting`）、完了監視・UI 同期（`GSPhotosIntegration`）。 |
| `Media/` | 写真・動画の取り出し。PhotoKit からの現行フルサイズ抽出・Live Photo ペアリング（`GSExporter`）、アルバム一括処理（`GSBatchImport`）。 |
| `Shared/` | 共通基盤。プロセス間通信プロトコル（`IPCProtocol`）、Mach/XPC 通信（`GSMachTransport`）、多言語ローカライズ（`GSLocalization`）、ランタイムチェック。 |
| `Daemon/` | 脱獄用デーモン（`gotohpd`）。Mach サービスの提供、クライアント認証（audit token 検証）、電源・通信状況の監視。 |
| `internal/service/` | Go 言語によるアップロードキューエンジン。ジョブ永続化（`state.go`）、キュー管理（`queue.go`）、ライフサイクル復旧（`engine.go`）。 |
| `GotohpCore/` | [xob0t/gotohp](https://github.com/xob0t/gotohp) のコアコード（upstream）と、iOS 向けに適用するオーバーレイ差分。 |

---

## 🔄 データフローとアップロード処理

### 1. メディアの抽出 (Media Export)
- 写真の選択時や Google フォト標準バックアップのトリガー時に、`Media/GSExporter` が PhotoKit (`PHAssetResourceManager`) を通じてメディアを一時領域に書き出します。
- **現行フルサイズの優先（Issue #69）**:
  - `PHAssetResourceTypeFullSizePhoto` / `FullSizeVideo`（ユーザーの編集、ポートレート効果、カメラのアスペクト比クロップ等を反映した現行フルサイズ）を原本リソースより優先して抽出します。追加の再エンコードは行いません。
- **RAW+JPEG の両方抽出**:
  - RAW と JPEG/HEIC が共存するアセットでは、現行の編集済み JPEG/HEIC 画像と元の RAW の両方をエクスポートします（編集済み画像を優先する規則は JPEG/HEIC 側に適用）。RAW 単独のアセットは RAW 形式をそのまま保持します。
- **Live Photo のペアリング（Issue #69）**:
  - 静止画と対になる動画リソースを正確に対応付けます。編集済み静止画には `FullSizePairedVideo`、未編集静止画には `PairedVideo` を選択します。
  - 編集済みペアが不完全な場合は、古い元リソースへ暗黙に戻さずエラーとして検出し、不整合なアップロードを防止します。
- **安全なメモリ管理（Issue #70）**:
  - 一括インポート（`GSBatchImport.m`）のチャンクごとの `autoreleasepool` 内で、ポインタ引数 `NSError **` に直接代入せず、強参照で保持してプール外へ渡すことで、解放済みエラー参照（zombie pointer）によるクラッシュを防いでいます。

### 2. ステージングとキュー登録 (Staging & Queueing)
- 一時ファイルは Go コアの専用ステージング領域にコピーされ、サイズ整合性とハッシュ値（SHA-1 等）が検証されます。
- ステージング完了後、キューの永続状態（`state.json`）がアトミックに書き込まれ、アップロード待ちジョブとして確定します。
- **未完了ジョブの上限管理（Issue #71）**:
  - キュー上限（`MaxJobs = 10000`）は、待機中・実行中の未完了ジョブのみに適用されます。完了・キャンセル済みの履歴は削除されずに保持され、重複検出に利用されます。これにより、1 万件を超える大規模ライブラリも履歴を消去することなく継続してインポートできます。

### 3. アップロード実行 (Upload Execution)
- キューワーカーがジョブを取り出し、現在の Google アカウントの認証情報と Pixel 端末プロファイル（Pixel XL 等）を用いて Google フォトサーバーと HTTPS 通信します。
- サーバー側のハッシュ照合（重複チェック）、アップロードトークンの取得、バイナリ転送、およびコミット処理を行います。
- **RAW+JPEG の場合**: 1 つのキュージョブから編集済み JPEG/HEIC と元の RAW をそれぞれ別々の写真としてアップロードし、両方の成功を確認してからジョブを完了します。
- **Live Photo の場合**: 静止画と動画の 2 つのリソースをメタデータ（StillImageTime 等）とともに関連付け、Google フォト上で 1 つの再生可能な Live Photo としてコミットします。

### 4. 完了後のステータス同期 (Reconciliation)
- アップロードが完了すると、`Native/GSPhotosIntegration` を通じて Google フォト内部の同期処理（`fetchData` 等）が呼び出され、UI 上で対象の写真が「バックアップ完了」として反映されます。

---

## 🔑 認証とトークンの管理

- **シームレスなトークン取得**:
  - Google フォトの内部 SSO サービス（`PHSAccountManagerImpl`）を利用し、ログイン中のアカウントから OAuth Bearer トークンを直接取得します。手動でのトークン取得や入力は不要です。
- **メモリ内保持と自動更新**:
  - トークンはメモリ内でのみ保持され、ディスク上のログや設定ファイルには一切平文保存されません。
  - 脱獄版ではデーモン内でのトークン保持期限を最大 5 分とし、期限切れの際は Google フォトの復帰時に自動的に再取得が行われます。
- **サイドロード時のログイン補正（Issue #68）**:
  - Jailed 版では、Bundle ID の変更等によって Google SSO の認証がブロックされる現象を防ぐため、リクエスト時の識別子や Keychain アクセスグループを自動的に正規の識別子へ補正します。
  - この補正フックは、ホストフレームワークや LiveContainer ゲスト環境の初期化後にも再確認されます。

---

## 🛡️ 耐障害性と永続化 (Durability)

- **アトミックな状態保存**:
  - ジョブの状態変更（Pending / Uploading / Completed / Failed）は、常に `fsync` とファイルのアトミック置換によってディスクに安全に保存されます。
- **クラッシュ・強制終了からの復旧**:
  - アプリの強制終了や端末の再起動が発生した場合、次回起動時に前回の状態が検査され、中断されたジョブは安全に `Pending`（再試行待ち）へ戻されて自動再開されます。
- **重複アップロードの抑止**:
  - アップロード前にサーバー側でのハッシュ照合を行い、すでにライブラリに存在するファイルは即座にコミット処理へ移行します。
