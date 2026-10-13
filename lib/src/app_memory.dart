import 'package:flutter/widgets.dart';

/// Posters are at most 240 x 426; a small cache is sufficient for revisits.
class AppMemory with WidgetsBindingObserver {
  AppMemory({ImageCache? cache})
    : _cache = cache ?? PaintingBinding.instance.imageCache;

  final ImageCache _cache;

  void attach() {
    _cache.maximumSizeBytes = 16 * 1024 * 1024;
    _cache.maximumSize = 48;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  void _trim() {
    _cache.clear();
    _cache.clearLiveImages();
  }

  @override
  void didHaveMemoryPressure() => _trim();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _trim();
    }
  }
}
