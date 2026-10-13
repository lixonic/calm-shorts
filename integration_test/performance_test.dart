import 'package:calm_reels/main.dart' as app;
import 'package:calm_reels/src/activity_sound.dart';
import 'package:calm_reels/src/playback_metrics.dart';
import 'package:calm_reels/src/reel_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.calmshorts/performance');

  Future<Map<String, dynamic>> memory() async => Map<String, dynamic>.from(
    await channel.invokeMethod<Map>('memory') ?? {},
  );

  Future<void> waitForVideo(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!tester
        .widgetList<VideoPlayer>(find.byType(VideoPlayer))
        .any((player) => player.controller.value.isInitialized)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Video did not become playable');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'native playback, resource bounds, lifecycle restoration, and audio',
    (tester) async {
      expect(
        monitorPlayback,
        isTrue,
        reason: 'Run with --dart-define=CALM_PERF=true',
      );
      final start = Stopwatch()..start();
      app.main();
      await tester.pump();
      await waitForVideo(tester);
      final firstPlayableMs = start.elapsedMilliseconds;
      final before = await memory();
      if (const bool.fromEnvironment('CALM_REQUIRE_16KB')) {
        expect(before['pageSizeBytes'], 16384);
      }
      final steps = const bool.fromEnvironment('CALM_FULL_SESSION') ? 399 : 100;
      await binding.watchPerformance(() async {
        for (var index = 0; index < steps; index++) {
          final next = find.byTooltip('Next');
          if (next.evaluate().isEmpty) break;
          await tester.tap(next);
          await tester.pump(const Duration(milliseconds: 400));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            PlaybackMetrics.live,
            lessThanOrEqualTo(4),
            reason: 'Controllers accumulated at step $index',
          );
        }
      }, reportKey: 'swipeFrames');
      final afterSwipes = await memory();

      // Ensure the current card is a video and stop it before the lifecycle probe.
      while (tester
          .widgetList<ReelPlayer>(find.byType(ReelPlayer))
          .every((p) => !p.isCurrent)) {
        await tester.tap(find.byTooltip('Next'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await waitForVideo(tester);
      if (find.byTooltip('Pause').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Pause'));
        await tester.pump();
      }
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer).first)
          .controller;
      final position = await player.position ?? Duration.zero;
      // Exercises Dart lifecycle cleanup with actual Android decoders. This is not
      // an OS background-memory sample; profile_android.py performs that check.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(PlaybackMetrics.live, 0);
      expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
      final afterHiddenCleanup = await memory();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await waitForVideo(tester);
      final restored = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer).first)
          .controller;
      expect(restored.value.isPlaying, isFalse);
      expect(
        (restored.value.position - position).inMilliseconds.abs(),
        lessThan(600),
      );

      // Test the bundled AAC on the native backend as well as the visual feed.
      final sound = OfflineActivitySound();
      final audio = sound.play('assets/activities/voices-3.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sound.stop();
      await audio.timeout(const Duration(seconds: 15));
      expect(PlaybackMetrics.live, lessThanOrEqualTo(2));
      final snapshots = {
        'before': before,
        'afterSwipes': afterSwipes,
        'afterSimulatedHiddenCleanup': afterHiddenCleanup,
        'restored': await memory(),
      };
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'firstPlayableMs': firstPlayableMs,
        'swipeStepsRequested': steps,
        'memory': snapshots,
        'playback': PlaybackMetrics.snapshot(),
        'cacheBudgetBytes':
            PaintingBinding.instance.imageCache.maximumSizeBytes,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(PlaybackMetrics.live, 0);
      expect(PlaybackMetrics.releaseErrors, 0);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
