# Build and content guide

[Back to the project and preview screenshots](../README.md)

An offline Flutter viewer for the CALM SHORTS collection, with a separate browser admin for managing content on your computer. The current bundle contains **334 unique videos, all portrait**. The fullscreen viewer plays this portrait collection; the admin provides content folders for managing uploads. Filename themes do not control playback order.

Each session plays the portrait videos in a shuffled order without repeating them. Swiping back intentionally revisits your viewing history. Videos advance when they finish, and you can swipe ahead whenever you like. Tap a video to pause or resume it, and use the sound control to mute or unmute playback. Quiet pauses and optional counting activities appear between videos at an editable interval (initially five videos). The viewer does not display video names or titles.

Videos are bundled inside the APK. Playback requires no account, network connection, or storage permission. The Android package is `dev.calmshorts.reels`, and the app supports Android 7.0 or later (API 24).

## Local content admin

The admin is a tool for your computer, **not a screen inside the Android app**. It runs on localhost without a login. From the repository root, with Python 3 and FFmpeg installed, run:

```bash
python3 tools/admin_server.py
```

Open [the local admin](http://127.0.0.1:8767/admin/). The sidebar contains **All videos**, **Portrait**, **Text prompts**, and **Recently removed**. You can search, switch between grid and list views, preview videos, edit library names, select multiple files, and upload or drag files into the window. Library names are only shown in the admin.

- Video uploads are automatically converted to H.264/AAC MP4s and JPEG posters in `assets/videos/` and `assets/posters/`, and added to `assets/library.json`. Aspect folders are assigned automatically. Raw uploaded originals are retained locally in `.local-admin/originals/`; they are excluded from Git and the APK. MP4, MOV, M4V, MKV, WebM, and AVI inputs are supported, up to 2 GB per input and under 100 MB per prepared file.
- Add or edit prompt text and choose its activity type (quiet pause, fingers, leaves, stars, hellos, chimes, or memory). Counts are picked from one to five. You can also import a TXT file with one prompt per nonempty line. JSON imports accept a list of strings or a `prompts` list containing objects with `line` fields and optional `activity` fields. Valid activity values are `notice`, `fingers`, `leaves`, `stars`, `voices`, `chimes`, and `memory`. Plain text imports create quiet pauses. Existing activity types survive text-only edits. Prompts and spacing are saved in `assets/prompts.json`, shared by the browser viewer and Flutter app. Removing all prompts disables interstitial prompts.
- **Remove from APK** moves the selected video and poster out of `assets/` into `.local-admin/trash/` and removes its catalog entry. Removed prompts leave the prompt catalog. These items are recoverable using **Restore**, stay on this computer, and are ignored by Git and APK builds.
- Changes save locally immediately. Open a fresh viewer session to see new content. Existing installations on phones change only after installing a newly built APK.

When ready, commit and push the changes, including file removals:

```bash
git add -A
git commit -m "Update local content library"
git push
```

GitHub Actions verifies that the video files exactly match the catalog and packages the current videos and prompts. It also checks that counting sounds match their source files and that no admin, local trash, or incoming original files appear in the APK. The admin itself does not commit or push to GitHub. Stop the local server with Ctrl+C. It binds only to `127.0.0.1`; cross-origin changes and requests using non-local hosts are rejected.

Run the admin tests (they create their own temporary content, without editing your library):

```bash
python3 -m unittest discover -s tools/tests -v
```

## Preview the viewer

The admin's **Open viewer** link opens the browser preview. You can also serve the `preview/` directory without the admin, using the same prepared video and prompt catalogs. From the app project directory, start a local server:

```bash
python3 -m http.server 8765 --bind 127.0.0.1
```

Open [the local preview](http://127.0.0.1:8765/preview/) in your browser. Use a phone-sized window, swipe or scroll to move through videos, or use the arrow keys and Previous/Next controls. Try pause and sound. The preview starts muted to support browser autoplay. The installed APK contains the videos and prompts and does not need this server.

## Get an APK with GitHub Actions

Use this **`calm-reels` directory as the repository root** so `.github/workflows/build-apk.yml` is at the top of the GitHub repository. Include the prepared videos and catalogs in `assets/`; they are required for an offline build.

1. Add the app project to a GitHub repository with Actions enabled.
2. Open **Actions → Build Android APK → Run workflow**. Pushing changes also starts a build; pull requests run the same checks with personal test signing.
3. Wait for formatting, analysis, tests, and the Android build to pass.
4. For a successful build on `main`, download [Calm-Reels.apk](https://github.com/lixonic/calm-shorts/releases/latest/download/Calm-Reels.apk) from the public release. No GitHub sign-in is required. The same link points to the latest successful build.
5. Copy the APK to your Android phone, open it, and allow that file manager or browser to install the app when Android prompts you.

The public release contains the APK directly and a SHA-256 checksum. Release downloads have no seven-day expiry. The workflow also retains an Actions copy for **1 day**; that copy requires GitHub sign-in. Builds on other branches and pull requests provide only the Actions copy. See [GitHub's release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) and [artifact documentation](https://docs.github.com/en/actions/tutorials/store-and-share-data).

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

Byte-identical duplicate copies are skipped when adding videos. Individual clips and assembled edits both remain available. The original collection is unchanged; the app uses prepared copies and a catalog under `assets/`.

The active portrait bundle contains **456.0 MB of videos** plus **3.8 MB of posters** and **0.2 MB of counting sounds**, about **460 MB total** before the app code and Android libraries are added. These are decimal MB. The preparation summary and manifest retain the initial compression measurements and original source mappings. The final APK size is measured after building.

| File or directory | Purpose |
| --- | --- |
| `assets/library.json` | Playback catalog, grouped only by aspect ratio. |
| `assets/prompts.json` | Editable prompt collection and spacing between videos. |
| `assets/videos/` | Prepared MP4 videos named by catalog ID. |
| `assets/posters/` | JPEG thumbnails shown while a video loads. |
| `assets/activities/` | Offline AAC recordings containing one to five hellos or chimes. |
| `assets/new-videos/` | Incoming originals, excluded from Git and APK builds. |
| `tools/media_preparation_summary.json` | Measured media sizes and preparation settings. |
| `tools/media_preparation_manifest.json` | Mapping from original files to bundled copies. |

For new content, use the local admin. If you place originals in `assets/new-videos/`, upload them through the admin to create the official copies before deleting that incoming folder. The originals in that folder are ignored by Git and are never included in the APK. To recreate the initial collection using its original external catalog, install FFmpeg and explicitly provide the original media location:

```bash
python3 tools/prepare_media.py \
  --source-root /home/lixon/Documents/CALM-SHORTS \
  --catalog /home/lixon/Documents/CALM-SHORTS/catalog/video_catalog.json
```

This bulk preparation command replaces the video catalog with the source catalog's selection; use the admin for routine additions and removals.

Copies use H.264 video and preserve the original aspect ratio without cropping or upscaling. Portrait videos stay at 720 × 1280 or smaller. New preparations use the `fast` preset, CRF 27, a 1.4 Mbps ceiling, and 64 kbps AAC audio; silent clips stay silent. Smaller JPEG posters keep their original dimensions. The optimization pass kept 74 previous video copies when a new encode was larger, and used the smaller new copies for the other 260. All 334 originals remain available locally. The manifest records each copy's actual video settings and hashes. To verify the prepared bundle:

```bash
python3 tools/prepare_media.py --verify-bundle
```

Bundling every video makes the repository, build downloads, and installed app substantially larger than a typical player. Allow enough room on the phone for both the APK download and installation. GitHub Actions artifact storage is account-wide: the [included allowance depends on your GitHub plan](https://docs.github.com/en/actions/reference/limits#storage-limits-for-all-github-hosted-runners). The APK and optional future-use Play bundle share that storage allowance, so check available storage or billing before repeated builds. Temporary build artifacts are retained for one day; public release downloads remain available. Remove unneeded build artifacts after downloading them, or account for the storage in your GitHub plan.

The prepared files are tracked in ordinary Git; do not ignore `assets/videos/`. GitHub rejects individual ordinary Git files over 100 MiB. Future media that exceeds that size needs a different storage approach before it is committed. See [GitHub's large-file guidance](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).

## Device verification

The automated checks verify the app source, feed logic, media metadata, APK signature, and presence of every video and poster inside the APK. On the target phone, test portrait playback, rapid swiping, sound, pause/resume, counting activities, listening and stopping cues, large text, backgrounding the app, and a full offline launch in airplane mode. Device installation and hardware video playback still need to be verified on an Android phone.

## Activity audio and prompt data

The counting recordings are committed to `assets/activities/`. They contain real, separated audible cues. Recreate them on a computer with FFmpeg's [Flite filter](https://ffmpeg.org/ffmpeg-filters.html#flite) available:

```bash
python3 tools/prepare_activity_audio.py
```

The `slt` voice says “Hello”; chimes are synthesized in Python. Quiet, mono AAC copies are used by both the browser and the app. Synthesis is a build-time operation. The installed app plays bundled recordings through the existing media player.

A prompt entry can include an activity:

```json
{"id":"p02","line":"How many fingers are held up?","activity":"fingers"}
```

Keep instructions consistent with the selected activity. The count and aurora colors are chosen once for each occurrence in the session and retained when navigating back. Missing `activity` fields remain compatible and mean `notice`.

The previous breathing-prompt collection was backed up locally at `.local-admin/backups/prompts-before-activities-20261013.json` when it was replaced. This backup is excluded from Git and APKs.

## Performance and future Play bundle

The current workflow also creates an AAB, checks its bundled content, and measures the largest compressed download with Google's pinned bundletool. Use **keep_play_bundle** when manually running the workflow to keep an AAB download. Its size/content checks run on every build, while retaining that extra large artifact is optional. This is a future-use build artifact; the current personal signing mode is for testing, and the workflow does not submit to Google Play. Both APK and AAB enforce project size budgets.

Public APK publishing waits for native playback/resource tests on a 16 KB Android emulator. See [the performance guide](PERFORMANCE.md) for reports, physical-phone profiling commands, and the distinction between emulator compatibility tests and real-device performance measurements.
