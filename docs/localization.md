# 多言語ローカライズ手順 (Localization)

Gunshot は、日本語と英語に標準対応しているほか、簡体中文・ベトナム語のカタログも備えています。
端末の言語設定に応じて自動で切り替わるほか、「GoToHP の設定」→「表示」→「言語」から手動で表示言語を切り替えることも可能です。

翻訳カタログはバイナリ内に直接埋め込まれているため、サイドロード時や LiveContainer 利用時にも追加のリソースファイル（`.bundle`）は不要です。

---

## 📁 翻訳ファイルの配置

翻訳カタログは `Localization/` ディレクトリ内の JSON ファイルで管理されています。

- `Localization/en.json` (英語カタログ / フォールバックキー)
- `Localization/ja.json` (日本語カタログ)
- `Localization/zh-hans.json` (簡体中文カタログ)
- `Localization/vi.json` (ベトナム語カタログ)

キー名には原則として英語のフォールバック文字列そのものが使用されます。

---

## ✍️ 翻訳の修正・追加手順

既存の文言を修正したり、新しい文字列を追加する手順は以下の通りです：

1. **カタログ JSON を編集する**:
   - `Localization/*.json` にキーと翻訳文を追加・修正します。
   - 書式指定子（`%@`, `%d`, `%lu` 等）が含まれる場合は、すべての言語で順序と型が一致していることを確認してください。
2. **コード内で文字列を参照する**:
   - Objective-C コード内では `GSL(@"English fallback text")` マクロを使用します。
3. **ヘッダーファイルを自動生成する**:
   - JSON カタログの変更を C/Objective-C 用のヘッダー（`Shared/GSLocalization.generated.h`）に反映させるため、以下のスクリプトを実行します：
   ```sh
   python3 scripts/localization.py
   ```
4. **整合性チェックを実行する**:
   - 抜け漏れやフォーマットエラーがないかを検証します：
   ```sh
   python3 scripts/localization.py --check
   ```
5. **テストを実行する**:
   - ローカライズ単体テストを実行して動作を確認します：
   ```sh
   clang -fobjc-arc -framework Foundation tests/localization.m -o .build/localization-test
   .build/localization-test
   ```

---

## 🌐 新しい言語を追加する場合

新しい言語を追加する場合：

1. `Localization/<lang_code>.json` を作成し、翻訳を追加します。
2. `UI/GSPanel.m` の言語選択メニュー（`GSSettingsLanguage`）に新しい言語コードと表示名を追加します。
3. `python3 scripts/localization.py` を実行してヘッダーを再生成します。
4. アプリを実行し、設定画面から言語を切り替えてレイアウト崩れがないか確認します。
