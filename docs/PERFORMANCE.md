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

## Profile a connected Android phone

Use a physical phone for meaningful speed, memory, and battery comparisons. An emulator checks compatibility and behavior; its CPU/GPU timing does not predict a phone's smoothness. [Flutter profiling guidance](https://docs.flutter.dev/perf/ui-performance).

Install Flutter 3.47.0, Java 17, Android SDK/platform-tools, authorize USB debugging on the phone, and use its explicit serial from `adb devices`. From the project directory:

```bash
flutter pub get --enforce-lockfile
flutter drive --profile \
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
