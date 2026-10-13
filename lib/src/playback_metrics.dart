/// Compiled out of normal builds. Used by the on-device performance harness.
const monitorPlayback = bool.fromEnvironment('CALM_PERF');

class PlaybackMetrics {
  static int live = 0;
  static int peak = 0;
  static int created = 0;
  static int disposed = 0;
  static int releaseErrors = 0;
  static final initializationMs = <int>[];

  static void opened() {
    if (!monitorPlayback) return;
    created++;
    live++;
    if (live > peak) peak = live;
  }

  static void closed({bool failed = false}) {
    if (!monitorPlayback) return;
    if (failed) releaseErrors++;
    disposed++;
    live--;
  }

  static Map<String, Object> snapshot() => {
    'liveControllers': live,
    'peakControllers': peak,
    'createdControllers': created,
    'disposedControllers': disposed,
    'releaseErrors': releaseErrors,
    'initializationMs': List<int>.of(initializationMs),
  };
}
