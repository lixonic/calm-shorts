# Calm Reels

An offline Flutter viewer for the CALM SHORTS collection. Swipe vertically through a random mix of videos, with separate **Portrait** and **Landscape** feeds. The collection includes all **324 unique videos**: **302 portrait** and **22 landscape**. Filename themes are not used to filter or order the feed.

Each feed plays every video once before starting a newly shuffled cycle. It avoids repeating the last video immediately when a new cycle begins. Swiping back intentionally revisits your viewing history. Videos advance when they finish, and you can swipe ahead whenever you like. Tap a video to pause or resume it, and use the sound control to mute or unmute playback. The viewer does not display video names or titles.

Videos are bundled inside the APK. Playback requires no account, network connection, or storage permission. The Android package is `dev.calmshorts.reels`, and the app supports Android 7.0 or later (API 24).

## Preview the viewer

The `preview/` directory contains a browser preview using the same prepared video library and shuffled playback behavior. From the app project directory, start a local server:

```bash
python3 -m http.server 8765 --bind 127.0.0.1
```

Open [the local preview](http://127.0.0.1:8765/preview/) in your browser. Use a phone-sized window, swipe or scroll to move through videos, or use the arrow keys and Previous/Next controls. Switch between Portrait and Landscape, and try pause and sound. The preview starts muted to support browser autoplay. The installed APK contains the videos and does not need this server.

## Get an APK with GitHub Actions

Use this **`calm_reels` directory as the repository root** so `.github/workflows/build-apk.yml` is at the top of the GitHub repository. Include the prepared videos and catalog in `assets/`; they are required for an offline build. Upload this app project, rather than the parent folder containing the original collection.

1. Add the app project to a GitHub repository with Actions enabled.
2. Open **Actions → Build Android APK → Run workflow**. Pushing changes also starts a build; pull requests run the same checks with personal test signing.
3. Wait for formatting, analysis, tests, and the Android build to pass.
4. For a successful build on `main`, download [Calm-Reels.apk](https://github.com/lixonic/calm-shorts/releases/latest/download/Calm-Reels.apk) from the public release. No GitHub sign-in is required. The same link points to the latest successful build.
5. Copy the APK to your Android phone, open it, and allow that file manager or browser to install the app when Android prompts you.

The public release contains the APK directly and a SHA-256 checksum. Release downloads have no seven-day expiry. The workflow also retains an Actions copy for **7 days**; that copy requires GitHub sign-in. Builds on other branches and pull requests provide only the Actions copy. See [GitHub's release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) and [artifact documentation](https://docs.github.com/en/actions/tutorials/store-and-share-data).

The build uses Flutter **3.47.0** and pinned action commits. It installs Java 17 and uses the generated AGP 9.1.0 / Gradle 9.3.1 Android project to create one release-mode APK containing both 32-bit ARM and 64-bit ARM support for Android phones. These Gradle and Java versions match the [Android plugin compatibility requirements](https://developer.android.com/build/releases/agp-9-1-0-release-notes#compatibility). After a verified build on `main`, a separate job publishes the APK to GitHub Releases and updates the public download link. Only that publishing job has repository write permission. The workflow does not publish to Google Play.

## Signing and repeat installations

The first build works without signing secrets. It produces an installable personal test APK signed with the Android development key. GitHub runners do not share that key, so a later APK may require uninstalling the previous personal build first. Android requires the same signing key to update an existing app. See [Flutter's Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app).

For repeatable updates, create one private upload keystore and save these four repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The whole keystore file encoded as base64. |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password. |
| `ANDROID_KEY_ALIAS` | The signing key's alias. |
| `ANDROID_KEY_PASSWORD` | The signing key's password. |

Provide all four secrets together. The workflow stops with a clear error if only some are supplied. Pull-request builds do not use these secrets. The keystore and signing properties are removed from the runner after each build and are excluded from Git.

Create the key once on a machine with Java installed:

```bash
keytool -genkeypair -v -keystore calm-reels-upload.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias calm-reels
base64 -w 0 calm-reels-upload.jks > calm-reels-upload.base64.txt
```

Keep the keystore and passwords backed up privately. Never commit the keystore or the base64 text file. Changing from a personal test build to your private signing key requires uninstalling the personal build once.

To use that same private key locally, create `android/key.properties` with these fields, and place the keystore at the indicated path relative to `android/`:

```properties
storeFile=calm-reels-upload.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=calm-reels
keyPassword=YOUR_KEY_PASSWORD
```

## Run or build locally

Install the Flutter version specified by `FLUTTER_VERSION` in `.github/workflows/build-apk.yml`, the Android SDK, and Java 17. Attach an Android phone with USB debugging enabled for a local run.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

To build an APK:

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

The local output is `build/app/outputs/flutter-apk/app-release.apk`. Local builds use the same signing fallback as Actions when `android/key.properties` is absent.

## Bundled media and storage

The eight byte-identical duplicate copies are excluded. Individual clips and assembled edits both remain available. The original collection is unchanged; the app uses prepared copies and a catalog under `assets/`.

The completed bundle contains **545.1 MB of videos** plus **4.9 MB of posters**, or **550.0 MB total** before the app code and Android libraries are added. The video copies are approximately **77% smaller** than the original 2.34 GB collection. These are decimal MB; the whole media bundle is about 524.5 MiB. The final APK size is measured after building.

| File or directory | Purpose |
| --- | --- |
| `assets/library.json` | Playback catalog, grouped only by aspect ratio. |
| `assets/videos/` | Prepared MP4 videos named by catalog ID. |
| `assets/posters/` | JPEG thumbnails shown while a video loads. |
| `tools/media_preparation_summary.json` | Measured media sizes and preparation settings. |
| `tools/media_preparation_manifest.json` | Mapping from original files to bundled copies. |

To recreate the media from this project directory, keep the original collection and `catalog/video_catalog.json` in the parent directory, install FFmpeg, and run:

```bash
python3 tools/prepare_media.py
```

Copies use H.264 video and preserve the original aspect ratio without cropping or upscaling. They are limited to 720 × 1280 for portrait and 1280 × 720 for landscape, with CRF 25 and a 1.8 Mbps video ceiling. The default encoding preset is `veryfast`; 29 previously verified copies made with `fast` were reused, while 295 use `veryfast`. The per-file manifest records each copy's actual settings. Existing audio is encoded as 96 kbps AAC; clips with no audio remain silent. To inspect the prepared bundle without needing any originals or performing another encode:

```bash
python3 tools/prepare_media.py --verify-bundle
```

Bundling every video makes the repository, build downloads, and installed app substantially larger than a typical player. Allow enough room on the phone for both the APK download and installation. GitHub Actions artifact storage is account-wide: the [included allowance depends on your GitHub plan](https://docs.github.com/en/actions/reference/limits#storage-limits-for-all-github-hosted-runners). The media bundle alone exceeds GitHub Free's 500 MB included artifact allowance, so check available storage or billing before running an APK build. Remove unneeded build artifacts after downloading them, or account for the storage in your GitHub plan.

The prepared files are tracked in ordinary Git; do not ignore `assets/videos/`. GitHub rejects individual ordinary Git files over 100 MiB. Future media that exceeds that size needs a different storage approach before it is committed. See [GitHub's large-file guidance](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).

## Device verification

The automated checks verify the app source, feed logic, media metadata, APK signature, and presence of every video and poster inside the APK. On the target phone, test portrait and landscape playback, rapid swiping, sound, pause/resume, backgrounding the app, and a full offline launch in airplane mode. Device installation and hardware video playback still need to be verified on an Android phone.
