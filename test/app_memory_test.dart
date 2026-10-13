import 'package:calm_reels/src/app_memory.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cache extends ImageCache {
  int trims = 0;
  int liveTrims = 0;
  @override
  void clear() {
    trims++;
    super.clear();
  }

  @override
  void clearLiveImages() {
    liveTrims++;
    super.clearLiveImages();
  }
}

void main() {
  testWidgets(
    'hidden states trim caches; brief overlays retain them; disposal unsubscribes',
    (tester) async {
      final cache = _Cache();
      final memory = AppMemory(cache: cache)..attach();
      final baseline = cache.trims;
      expect(cache.maximumSizeBytes, 16 * 1024 * 1024);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(cache.trims, baseline);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(cache.trims, baseline + 1);
      expect(cache.liveTrims, 1);
      tester.binding.handleMemoryPressure();
      expect(cache.trims, baseline + 2);
      memory.dispose();
      tester.binding.handleMemoryPressure();
      expect(cache.trims, baseline + 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
