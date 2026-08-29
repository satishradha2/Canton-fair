# Android Auto-Update Setup

This project is configured so every push to `main` can build a release APK and publish it to GitHub Releases.

Android does not allow a normal app installed from GitHub to silently replace itself. The app can check GitHub Releases and open the latest APK download, but Android will still ask the user to approve installation.

## One-time GitHub setup

1. Generate a release signing key on your machine:

   ```powershell
   .\scripts\create_android_signing_key.ps1
   ```

2. In GitHub, open:

   `Settings > Secrets and variables > Actions > New repository secret`

3. Add the four secrets printed by the script:

   `ANDROID_KEYSTORE_BASE64`
   `ANDROID_KEYSTORE_PASSWORD`
   `ANDROID_KEY_PASSWORD`
   `ANDROID_KEY_ALIAS`

4. Push to `main`.

The workflow `.github/workflows/android-apk-release.yml` will build a signed release APK and publish it as the latest GitHub Release.

## Important install rule

For updates to install over the old app, every APK must be signed with the same release key. After setting up GitHub signing, install the first APK from GitHub Releases. If you previously installed a debug APK from this computer, uninstall it once before installing the GitHub release APK.

## In-app update check

Open the app, go to `Settings > App updates`, and tap the row. The app checks the latest GitHub Release and opens the APK download when a newer build is available.
