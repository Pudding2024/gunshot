# GoToHP for iOS (Gunshot)

[English](README.md) · [日本語](README.ja.md)

**Gunshot (GoToHP for iOS)** is a tweak and injection library for the official iOS Google Photos app that spoofs your device as a Google Pixel, enabling original-quality unlimited cloud backups and custom upload workflows. It integrates an optimized iOS port of the Go core from [xob0t/gotohp](https://github.com/xob0t/gotohp).

It supports both **Jailbroken** environments (Rootless and Rootful) and **Jailed** environments (Sideloading, TrollStore, and LiveContainer).

---

## 🌟 Key Features

- **Pixel Spoofing Uploads**:
  - **Original Quality (Unlimited)**: Spoofs a Pixel XL (Pixel 1) to upload photos and videos in full original quality without consuming Google account storage quota.
  - **Storage Saver**: Spoofs a Pixel 2 for unlimited uploads in Storage Saver quality.
  - **Account Storage**: Spoofs a Pixel 8 for original quality using standard account quota.
- **Native Backup Routing**:
  - Intercepts Google Photos' standard manual and automatic backup triggers and routes them through the GoToHP queue.
  - Back up your library simply by using the Google Photos app normally.
- **Automatic Account Detection**:
  - Automatically detects the signed-in Google account and acquires OAuth tokens via Google Photos' existing SSO framework.
  - No need to extract or paste tokens manually.
- **Bulk Album Import**:
  - Bypasses the iOS system picker limitation (100 items per selection) by importing entire albums directly with batch processing.
  - The queue limit applies only to unfinished jobs, preserving completion history and deduplication across libraries of 10,000+ items.
- **Full Fidelity & Live Photo Support**:
  - Exports the current full-size PhotoKit rendition without additional re-encoding, preserving edits, portrait effects, and camera crops.
  - Uploads both the edited JPEG/HEIC and original RAW for RAW+JPEG assets, preserves RAW-only assets, and pairs the matching still and video components of **Live Photos**.
- **Native UI Integration**:
  - Integrates the "GoToHP Settings" menu directly into the Google Photos profile sheet.
  - Optional banner to display the authentic Google Pixel "Unlimited storage" badge.
- **Multilingual Support**:
  - Fully localized in English and Japanese (includes embedded Simplified Chinese and Vietnamese catalogs).

---

## 📱 Screenshots

<p>
  <img src="docs/images/unlimited-storage.png" width="240" alt="Unlimited storage card in Google Photos profile menu">
  <img src="docs/images/profile-menu.png" width="240" alt="GoToHP Settings entry in profile menu">
</p>
<p>
  <img src="docs/images/upload-settings.png" width="240" alt="Upload settings showing signed-in account and quality profiles">
  <img src="docs/images/backup-routing.png" width="240" alt="Native backup routing settings">
  <img src="docs/images/appearance-settings.png" width="240" alt="Appearance settings for language and unlimited badge">
</p>

---

## 📦 Packages & Environments

| Environment | Package | Execution Behavior |
| :--- | :--- | :--- |
| **Jailbreak (Rootless)** | `gotohp-tweak-rootless.deb` | Uploads via background daemon (`gotohpd`). Continues uploading even when the app is closed. |
| **Jailbreak (Rootful)** | `gotohp-tweak-rootful.deb` | Uploads via background daemon (`gotohpd`). Continues uploading even when the app is closed. |
| **Sideload / TrollStore / LiveContainer** | `gotohp-tweak-jailed.deb`<br>`GunshotJailed.dylib` | Runs embedded inside the Google Photos app. Active when the app is in the foreground. |

> [!TIP]
> Download ready-to-use packages from [Releases](https://github.com/tqmane/gunshot/releases) or the latest artifacts on [GitHub Actions](https://github.com/tqmane/gunshot/actions).

---

## 🚀 Installation

### 1. Sideloading / TrollStore / LiveContainer (Non-Jailbroken)
See the full [Jailed Installation Guide](docs/jailed.md) for detailed walkthroughs.

- **Using Sideloadly**:
  1. Open your decrypted Google Photos IPA in Sideloadly.
  2. Under **Advanced Options → Inject dylibs/frameworks**, add `gotohp-tweak-jailed.deb`.
     *Note: The deb bundles `CydiaSubstrate.framework`; keep Sideloadly's separate **Cydia Substrate** option unchecked to avoid duplicate injection. Leave **Substitute** and **Sideload Spoofer** disabled for normal use.*
  3. Start the installation to your device.
- **Using TrollStore or Manual Injection**:
  - Inject `gotohp-tweak-jailed.deb` into your decrypted IPA (using tools like Azule or Sideloadly Export) and install via TrollStore.
- **Using LiveContainer**:
  - Import `GunshotJailed.dylib` into the LiveContainer tweaks folder for Google Photos.

> [!IMPORTANT]
> **Inject and enable Gunshot BEFORE signing into your Google account.**
> GunshotJailed includes automatic SSO identifier and Keychain corrections to prevent sideload sign-in issues.
> If you encounter sign-in issues on specific older configurations, see the [legacy login workaround in the Jailed guide](docs/jailed.md#issue-68-legacy-login-workaround).

### 2. Jailbreak
1. Install `gotohp-tweak-rootless.deb` or `gotohp-tweak-rootful.deb` through your package manager (Sileo, Zebra, etc.).
2. Requires **libSandy 1.1.6+** from [opa334's repository](https://opa334.github.io/) as a dependency.
3. If Google Photos crashes upon launch, configure **Choicy** to inject only Gunshot into Google Photos.

---

## 📖 How to Use

1. **Launch Google Photos and Sign In**
   - GoToHP automatically connects to your active Google account in the background. No manual token setup needed.
2. **Review Upload Settings**
   - Tap your **Profile icon → GoToHP Settings**.
   - Choose your desired upload quality (Original / Storage Saver / Account Storage).
3. **Upload Photos & Videos**
   - **Automatic Native Backup**:
     - Turn on **Route manual and automatic backups through GoToHP** in settings (ensure Google Photos' built-in backup is also enabled).
     - Photos will automatically route through GoToHP's Pixel-spoofed queue. See [Native Backup Routing](docs/native-routing.md).
   - **Manual Upload**:
     - Tap **Uploads → Choose photos and videos** (up to 100 items per selection).
     - Or choose **Choose album** to queue entire albums at once (see [Bulk Import Guide](docs/bulk-import.md)).

> [!NOTE]
> - **Sideloaded (Jailed) builds**: Uploading occurs while Google Photos is active in the foreground. Keep the app open while uploading.
> - **Jailbroken builds**: Once media is staged into the queue, the background daemon handles the upload even if you close Google Photos.

---

## ⚙️ Quality Profiles

| Setting | Spoofed Device | Upload Policy |
| :--- | :--- | :--- |
| **Original** | Pixel XL (Pixel 1) | Original quality with zero Google account quota usage. |
| **Storage Saver** | Pixel 2 | High quality compressed by Google with zero quota usage. |
| **Account Storage** | Pixel 8 | Original quality consuming standard Google account quota. |

---

## 📚 Documentation

- [Documentation Portal](docs/README.md)
- [Jailed / Sideloading Guide](docs/jailed.md)
- [Native Backup Routing Guide](docs/native-routing.md)
- [Bulk Import & Troubleshooting](docs/bulk-import.md)
- [Development, Building & Testing](docs/development.md)
- [Architecture & Design Details](docs/architecture.md)
- [Device Validation Checklist](docs/device-validation.md)
- [Localization Guide](docs/localization.md)
- [Google Photos Analysis Index](docs/analysis/index.md)

---

## ⚠️ Disclaimer

This is an unofficial open-source project and is not affiliated with, authorized, or endorsed by Google LLC or Apple Inc. Provided **"as is", without warranty of any kind**. Google may change policies or backend APIs at any time, which could impact quota calculation or account standing. Always keep an independent backup of your original media. Google Photos binaries, signing certificates, and proprietary credentials are not distributed in this repository.

---

## 📄 License

- **Gunshot**: [GNU General Public License v3.0 or later](LICENSE) (C) 2026 tqmane
- **Bundled gotohp Core**: [MIT License](GotohpCore/upstream/LICENSE) (C) 2024 xob0t
- Other third-party dependencies retain their respective licenses (see `ThirdPartyNotices.txt` in release archives).
