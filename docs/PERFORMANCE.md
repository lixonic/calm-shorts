# Performance and build verification

Calm Reels 1.2 adds a 16 MiB / 48-entry poster cache, hidden-state cache trimming, direct lifecycle audio stopping, and decoder release after two seconds hidden. A brief inactive overlay pauses playback without destroying the player. Resuming recreates the player at its saved position and keeps pause/mute choices; revisiting a previous reel still starts that reel again. Memory pressure releases players immediately and recreates only the current one.

## What the automated build checks

`.github/workflows/build-apk.yml` produces the installable ARM APK and a future-use ARM AAB. Temporary signing remains enabled, as requested; nothing is uploaded to Google Play. A stable upload key is needed if Play publication is chosen later.

- Videos, posters, prompts, and counting sounds must match the current catalog byte-for-byte.
- Local admin, trash, and incoming originals must stay out of both archives.
- Native ELF load segments must support 16 KB pages. Native library ZIP payloads in the APK must also be aligned to 16 KB.
- Offline media is capped at **461 MB**, the universal phone APK at **495 MB**, and bundletool's largest compressed Play download at **480 MB**. These are project budgets with headroom, not Google's limits. Uploads and restores that would exceed the media budget are rejected before finalizing the change.
- The pinned Google bundletool JAR is checked against its SHA-256 digest before use.
- A 16 KB Android 15 emulator exercises native playback, 100 next actions and 20 backward swipes, controller resource bounds, position restoration after hidden cleanup, and bundled AAC stopping. It records first-playable timing, Flutter frame timings, process memory, and resource counts.
- A separate release APK probe uses actual Android Home/return transitions and records startup timing, foreground/background/restored `dumpsys meminfo`, power state, and battery diagnostics.
- Public APK publishing waits for both the build checks and the native smoke test.

The **Android-quality** and **Android-performance** artifacts in Actions contain diagnostic reports. The AAB is built and checked on each run; use the manual workflow’s **keep_play_bundle** checkbox to retain its download too. This avoids storing a second large artifact on every push. Development/test plugins are excluded from release by Flutter's Gradle plugin. Playback telemetry is enabled only by `CALM_PERF=true`; the native memory channel is available only in debug/profile builds.

## Verified release: 13 October 2026

[CI run 17](https://github.com/lixonic/calm-shorts/actions/runs/38375128991) passed both build verification and the native test before publishing [release apk-17-1](https://github.com/lixonic/calm-shorts/releases/tag/apk-17-1), from commit `c7be20f8e4db203e3cf7e64f6cb3cb716e19487e`.

- APK: **489,823,362 bytes (489.8 MB)**; largest bundletool compressed download: **466,358,117 bytes (466.4 MB)**; DEX: **1,725,176 bytes**.
- Android emulator used **16,384-byte pages**. All 100 next actions, 20 backward swipes, hidden cleanup, position/pause restoration, and sound stopping passed. Peak native player count was **3**, with **0 release errors**.
- First playable video: **2,183 ms from Dart entrypoint**. Anonymous RSS grew from **124,284 KiB** to **141,312 KiB** after the swipe exercise, with zero swap. These are emulator snapshots, not field metrics.
- Forward-test frame build P90 was **6.228 ms**, but raster P90 was **139.558 ms** on the software-rendered emulator. Playback compatibility passed; these results do **not** establish smooth rendering on phones. Physical-device profiling remains necessary.
- The release APK probe also completed actual Android Home/return transitions and recorded launch/memory/power diagnostics. Those reports are in the run's performance artifact.
- The public APK URL returned HTTP 200. Its published checksum matched GitHub's asset digest: `17f1edb8c9e1245a389d6aa775cbac996fb0554083a66126a3c1ee8ccf8a3018`.

## Profile a connected Android phone

Use a physical phone for meaningful speed, memory, and battery comparisons. An emulator checks compatibility and behavior; its CPU/GPU timing does not predict a phone's smoothness. [Flutter profiling guidance](https://docs.flutter.dev/perf/ui-performance).

Install Flutter 3.47.0, Java 17, Android SDK/platform-tools, authorize USB debugging on the phone, and use its explicit serial from `adb devices`. From the project directory:

```bash
flutter pub get --enforce-lockfile
flutter drive --profile --no-dds \
  --target=integration_test/performance_test.dart \
  --driver=test_driver/performance_driver.dart \
  --dart-define=CALM_PERF=true \
  -d DEVICE_SERIAL
```

To visit the full feed, add `--dart-define=CALM_FULL_SESSION=true`. The report is `build/integration_response_data.json`. The first-playable timing starts when the Dart app entrypoint runs; it is not the system's cold-start TTID. Memory snapshots include anonymous RSS, swap, RSS, PSS, and native heap. RSS plus swap snapshots are diagnostic measurements, not Google Play's aggregated 28-day P90 metric.

The integration test's hidden transition exercises the Dart lifecycle with real native decoders; its memory label explicitly says **simulated hidden cleanup**. For actual OS background behavior, build and install a normal release APK, then run:

```bash
flutter build apk --release --target-platform android-arm,android-arm64
python3 tools/profile_android.py \
  --serial DEVICE_SERIAL \
  --apk build/app/outputs/flutter-apk/app-release.apk
```

This collects `build/performance/android-release.json`. Installation uses `adb install -r` and never uninstalls an app. A signing mismatch stops the command rather than deleting existing data. The probe launches the app, presses Home for four seconds, then returns. Review the raw measurements and startup samples. Android vitals uses TTID for startup classification; the `am start -W` timing fields are useful local launch diagnostics but are not a substitute for vitals.

For a 16 KB phone/emulator, add `--dart-define=CALM_REQUIRE_16KB=true` to the integration command. A release artifact can also be inspected locally:

```bash
python3 tools/verify_android.py build/app/outputs/flutter-apk/app-release.apk
python3 tools/verify_android.py build/app/outputs/bundle/release/app-release.aab
```

## Remaining external validation

A physical lower-memory phone, a current Android phone, and a longer viewing session are still needed to assess real decoder latency, thermal behavior, wake locks, and device-specific smoothness. No physical Android device or local KVM emulator was available during implementation. If the app goes to Play later, use the pre-launch report and Android vitals; automated tests cannot establish population crash/ANR rates or certify Play approval.
