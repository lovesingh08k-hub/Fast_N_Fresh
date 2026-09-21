# FAST N FRESH — One-click Android releases

The project now supports a Play-Store-free release flow through GitHub Actions.

## What happens when you release

1. Open GitHub → **Actions** → **Release Android APK** → **Run workflow**.
2. Enter the new version, for example `1.5.33`.
3. Leave build number blank to auto-increment it, or enter one explicitly.
4. Enter release notes and choose whether the update is forced.
5. GitHub Actions installs Flutter, signs the APK with the production keystore,
   runs `flutter analyze`, builds the APK, creates a GitHub Release, and uploads:
   - `fast-n-fresh.apk`
   - `manifest.json`
6. The APK is published at the release download URL.
7. The installed app checks the stable `releases/latest/download/manifest.json`
   URL and detects the new build. It opens the APK download when the user taps
   **Update Now**.

## One-time GitHub setup

Add these repository secrets under **Settings → Secrets and variables → Actions**:

- `ANDROID_KEYSTORE_BASE64` — base64 contents of the SAME production keystore
  already used by the cafe's installed APK.
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `PRODUCTION_API_BASE_URL` — optional; if omitted, the current Render API URL
  built into the project is used.

### Create the base64 keystore value on Windows PowerShell

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\upload-keystore.jks")) | Set-Clipboard
```

Paste the clipboard contents into `ANDROID_KEYSTORE_BASE64`.

**Never commit the keystore, key.properties, or passwords to Git.**

## Critical signing rule

Every APK update must use the **same signing key** as the APK already installed
on the cafe device. If the installed `1.5.32` APK was signed with a different
keystore from the one configured in GitHub, Android will reject the new APK as an
update. In that case the old APK must be uninstalled before the new signing key
can be used, which may affect locally stored app data.

## Backend releases

Backend-only changes do not require an APK release when the installed Flutter
version already supports the changed API. Push the backend changes normally and
let Render deploy them.

Frontend Flutter changes require a new Android release. Use the workflow above.

## Important architecture detail

The app's update check uses the GitHub Releases manifest first, rather than
requiring Render to be awake. The existing `/api/public/app-update` endpoint is
kept as a backward-compatible fallback.
