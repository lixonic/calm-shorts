import 'dart:async';

import 'package:video_player/video_player.dart';

abstract class ActivitySound {
  /// Completes when the short recording finishes or is stopped.
  Future<void> play(String asset);
  Future<void> stop();
}

/// Uses the existing offline media player for bundled AAC audio. There is no
/// microphone, speech recognition, network voice, or automatic playback.
class OfflineActivitySound implements ActivitySound {
  VideoPlayerController? _controller;
  Completer<void>? _done;
  var _generation = 0;

  @override
  Future<void> play(String asset) async {
    final generation = _generation + 1;
    await stop();
    if (generation != _generation) return;
    final controller = VideoPlayerController.asset(asset);
    final done = Completer<void>();
    _controller = controller;
    _done = done;
    void observe() {
      if (done.isCompleted) return;
      if (controller.value.hasError) {
        done.completeError(StateError('Audio could not play'));
      } else if (controller.value.isCompleted) {
        done.complete();
      }
    }

    controller.addListener(observe);
    // Attach an error handler before initialization can emit an error.
    final completion = done.future;
    unawaited(completion.catchError((Object _) {}));
    try {
      await controller.initialize();
      if (generation != _generation) return;
      await controller.setVolume(0.6);
      if (generation != _generation) return;
      await controller.play();
      await completion;
    } finally {
      controller.removeListener(observe);
      if (identical(_controller, controller)) await stop();
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final controller = _controller;
    final done = _done;
    _controller = null;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
    if (controller != null) await controller.dispose();
  }
}
