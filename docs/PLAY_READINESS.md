# Google Play performance and optimization review

Reviewed **13 October 2026**, against source commit `8006efd` and the published **1.1.0 / version code 10** APK, release `apk-10-1`.

The app already has a suitable SDK target, small optimized Android code, and correctly aligned native libraries. The main improvement areas are hidden-state video resources, native-device performance measurements, and distribution of the large offline collection. This review does not certify runtime compliance: no Android device, emulator, or Play Console performance data was available.

## The new requirements

Google announced new technical-quality requirements on **26 August 2026**, with memory and code-optimization enforcement beginning **February 2027**. Runtime memory is evaluated using anonymous RSS plus swap, and a separate bitmap metric. Installed video files are not themselves anonymous memory. [Google's announcement](https://android-developers.googleblog.com/2026/08/app-quality-memory-optimization-secure-onboarding.html).

For the app category on a 4 GB device, the published P90 memory thresholds are **2 GB foreground** and **1 GB background**. Non-visible bitmap thresholds are **200 MB background / user-perceived service** and **400 MB cached**. Optimization, shrinking, and obfuscation must each reach **25%** where an app has **more than 10 MB of DEX code**. These are ceilings and applicability rules, not desirable engineering targets. [Technical-quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799?hl=en).

## Improvements implemented in 1.2

- Poster cache reduced from Flutter's default 100 MiB to **16 MiB / 48 entries**, with hidden-state and memory-pressure eviction.
- Video playback pauses directly on lifecycle events. After **two seconds hidden**, native decoders are disposed; resuming restores the saved position, pause state, and mute choice. Brief overlays keep the decoder. Memory pressure releases it immediately and recreates only the current video.
- Listening audio stops directly on lifecycle/memory-pressure events, independently of a UI redraw.
- The collection was prepared again from its original files, preserving all **334 videos** and current resolutions. Video size fell from **521.6 MB to 456.0 MB**, and smaller posters bring the media total to about **460 MB**. Larger candidate encodes were not adopted. [Compression sample measurements](../tools/media_optimization_benchmark.json).
- CI checks both ELF and APK ZIP alignment, 64-bit ARM support, byte-for-byte offline assets, signed archives, and project size budgets. The largest Play compressed download is measured with bundletool and capped at **480 MB** for headroom below Google's 500 MB base limit. [Current size limits](https://support.google.com/googleplay/android-developer/answer/9859372?hl=en).
- A native 16 KB emulator job exercises playback, repeated swipes, hidden cleanup/restoration, resource bounds, and AAC stopping. Reports include Flutter frame timings, initialization latency, process memory, OS background measurements, and wake-lock diagnostics. Publishing waits for that job.
- The workflow produces an AAB alongside the APK for future use. **Temporary signing remains in place**, as requested, and nothing is submitted to Play.

Implementation checks: **31 Flutter tests and 12 Python tests** passed, and analysis found no issues. The native CI job verifies the Android build and runtime; inspect its reports for the release you are assessing. [Performance guide](PERFORMANCE.md).

The earlier APK already targeted API 36, passed static 16 KB alignment checks, and contained only 1.73 MB of DEX. The SDK/R8 defaults remain suitable. The new release is checked again by CI; the earlier inspection below is historical evidence rather than a measurement of the new APK.

## Device checks needed before claiming readiness

1. Test a release/profile build on a lower-memory Android phone and a current Android phone, including a 16 KB environment. Capture CPU, decoder/buffer allocations, anonymous RSS plus swap, and bitmap/native memory while playing, swiping, hidden, and returning.
2. Run at least 100 rapid forward swipes and repeated backward swipes, then a full session. Verify native memory settles after disposal, sound never overlaps, and no decoder initialization or disposal errors appear.
3. Measure time to initial display and first usable video separately. Android vitals considers TTID excessive at **5 seconds cold, 2 seconds warm, and 1.5 seconds hot**. These are different from first-video readiness. [Startup metrics](https://developer.android.com/google/play/vitals/launch-time).
4. Capture Flutter frame timing during swipes and prompt interactions; at 60 Hz the UI frame budget is about **16.7 ms**. The UI refresh budget does not require re-encoding the source videos to 60 fps. [Core app quality](https://developer.android.com/docs/quality-guidelines/core-app-quality).
5. Background/lock the phone during video initialization, video playback, and listening. Check for stopped playback, reduced retained memory, clean restoration, and background CPU/wake locks. Excessive non-exempt wake locks can affect Play visibility under the current policy. [Wake-lock quality update](https://android-developers.googleblog.com/2026/03/how-whoop-decreased-excessive-partial.html).
6. Use a Play internal-test AAB and pre-launch report, then monitor Android vitals. Current overall bad-behavior thresholds include **1.09% user-perceived crashes** and **0.47% user-perceived ANRs**. These field rates cannot be established from local tests. [Android vitals](https://support.google.com/googleplay/android-developer/answer/9844486?hl=en).

For Play delivery, also replace the current personal development signing fallback with a stable upload key and produce an AAB. The existing [build guide](BUILD.md) explains the signing setup. The upcoming sign-in restoration requirement is inapplicable to this app's current account-free design; adding an account system would require revisiting it.

## APK inspection evidence

[Machine-readable inspection](play-apk-audit.json) records the release commit, packaged SDK levels, DEX size, merged permissions, and ELF/ZIP alignments. Only **339,300 bytes** of the public APK were fetched using validated HTTP byte ranges; this was a static binary inspection, not an installation, runtime test, or a replacement for signature verification.

The requested paragraph remains removed from the main README. Runtime and build improvements are implemented; physical-phone measurements and any future Play Console validation still need the corresponding device/account access.
