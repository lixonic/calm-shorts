import 'dart:async';

import 'package:calm_reels/src/reel_player.dart';
import 'package:calm_reels/src/video_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const _duration = Duration(seconds: 8);

VideoClip _clip(String id) => VideoClip(
  id: id,
  assetPath: 'assets/videos/$id.mp4',
  title: 'A quiet moment',
  aspectRatio: 9 / 16,
  durationSeconds: _duration.inSeconds.toDouble(),
  hasAudio: true,
);

void main() {
  late _VideoPlatform platform;
  late VideoPlayerPlatform previousPlatform;

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() async {
    await platform.closeStreams();
    VideoPlayerPlatform.instance = previousPlatform;
  });

  Future<void> pumpPlayer(
    WidgetTester tester, {
    bool current = true,
    bool active = true,
    bool paused = false,
    bool muted = true,
    VoidCallback? onFinished,
    VoidCallback? onTogglePause,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReelPlayer(
          key: const ValueKey('current'),
          clip: _clip('current'),
          isCurrent: current,
          active: active,
          paused: paused,
          muted: muted,
          onTogglePause: onTogglePause ?? () {},
          onFinished: onFinished ?? () {},
          onSkip: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> initializePlayers(WidgetTester tester) async {
    for (final id in platform.players.keys) {
      platform.initialize(id);
    }
    await tester.pump();
    await tester.pump();
  }

  Future<void> removePlayers(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    expect(platform.disposedIds, unorderedEquals(platform.players.keys));
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'only the active current clip plays; its preloaded neighbor pauses',
    (tester) async {
      var firstCurrent = true;
      Widget feed() => MaterialApp(
        home: Row(
          children: [
            for (final id in ['first', 'next'])
              Expanded(
                child: ReelPlayer(
                  key: ValueKey(id),
                  clip: _clip(id),
                  isCurrent: (id == 'first') == firstCurrent,
                  active: (id == 'first') == firstCurrent,
                  paused: false,
                  muted: true,
                  onTogglePause: () {},
                  onFinished: () {},
                  onSkip: () {},
                ),
              ),
          ],
        ),
      );

      await tester.pumpWidget(feed());
      await initializePlayers(tester);
      final first = platform.idFor('first');
      final next = platform.idFor('next');
      expect(platform.playingIds, {first});
      expect(platform.players[next]!.playCount, 0);
      expect(platform.players[next]!.pauseCount, greaterThan(0));

      firstCurrent = false;
      await tester.pumpWidget(feed());
      await tester.pump();
      expect(platform.playingIds, {next});
      expect(platform.players[first]!.playing, isFalse);

      await removePlayers(tester);
    },
  );

  testWidgets('pause, resume, and mute updates reach the existing player', (
    tester,
  ) async {
    var taps = 0;
    await pumpPlayer(tester, onTogglePause: () => taps++);
    await initializePlayers(tester);
    final player = platform.players.values.single;
    expect(player.playing, isTrue);
    expect(player.volume, 0);

    await tester.tap(find.byType(GestureDetector).first);
    expect(taps, 1);

    await pumpPlayer(tester, paused: true, muted: false);
    expect(player.playing, isFalse);
    expect(player.volume, 1);
    expect(platform.players, hasLength(1));

    await pumpPlayer(tester, paused: true);
    expect(player.playing, isFalse);
    expect(player.volume, 0);

    await pumpPlayer(tester);
    expect(player.playing, isTrue);
    expect(player.seeks, isEmpty);
    await removePlayers(tester);
  });

  testWidgets('completion advances once despite repeated end events', (
    tester,
  ) async {
    var finished = 0;
    await pumpPlayer(tester, onFinished: () => finished++);
    await initializePlayers(tester);
    final id = platform.players.keys.single;
    final player = platform.players[id]!;
    final initialPlays = player.playCount;

    platform.complete(id);
    platform.complete(id);
    await tester.pump();
    await tester.pump();
    expect(finished, 1);
    expect(player.playing, isFalse);
    expect(player.position, _duration);

    platform.complete(id);
    await tester.pump();
    await pumpPlayer(tester, muted: false, onFinished: () => finished++);
    expect(finished, 1);
    expect(player.playCount, initialPlays);
    expect(player.seeks, everyElement(_duration));
    await removePlayers(tester);
  });

  testWidgets(
    'completion while inactive is deferred until foreground resumes',
    (tester) async {
      var finished = 0;
      await pumpPlayer(tester, onFinished: () => finished++);
      await initializePlayers(tester);
      final id = platform.players.keys.single;
      final player = platform.players[id]!;

      await pumpPlayer(tester, active: false, onFinished: () => finished++);
      expect(player.playing, isFalse);
      platform.complete(id);
      await tester.pump();
      await tester.pump();
      expect(finished, 0);
      final playsBeforeResume = player.playCount;
      final seeksBeforeResume = player.seeks.length;

      await pumpPlayer(tester, onFinished: () => finished++);
      await tester.pump(const Duration(milliseconds: 16));
      expect(finished, 1);
      expect(player.playCount, playsBeforeResume);
      expect(player.seeks.length, seeksBeforeResume);
      expect(player.position, _duration);
      await tester.pump();
      expect(finished, 1);
      await removePlayers(tester);
    },
  );

  testWidgets('completion while explicitly paused advances after unpausing', (
    tester,
  ) async {
    var finished = 0;
    await pumpPlayer(tester, paused: true, onFinished: () => finished++);
    await initializePlayers(tester);
    final id = platform.players.keys.single;
    final player = platform.players[id]!;
    platform.complete(id);
    await tester.pump();
    await tester.pump();
    expect(finished, 0);
    expect(player.playCount, 0);

    await pumpPlayer(tester, onFinished: () => finished++);
    expect(finished, 1);
    expect(player.playCount, 0);
    expect(player.seeks, [_duration]);
    await removePlayers(tester);
  });

  testWidgets(
    'returning to a completed history clip rewinds and can finish again',
    (tester) async {
      var finished = 0;
      await pumpPlayer(tester, onFinished: () => finished++);
      await initializePlayers(tester);
      final id = platform.players.keys.single;
      final player = platform.players[id]!;
      platform.complete(id);
      await tester.pump();
      await tester.pump();
      expect(finished, 1);

      await pumpPlayer(
        tester,
        current: false,
        active: false,
        onFinished: () => finished++,
      );
      final playsBeforeReturn = player.playCount;
      await pumpPlayer(tester, onFinished: () => finished++);
      expect(player.seeks.last, Duration.zero);
      expect(player.position, Duration.zero);
      expect(player.playCount, playsBeforeReturn + 1);
      expect(player.playing, isTrue);
      expect(finished, 1);
      expect(platform.players, hasLength(1));

      platform.complete(id);
      await tester.pump();
      await tester.pump();
      expect(finished, 2);
      await removePlayers(tester);
    },
  );

  testWidgets('a noncurrent completed neighbor never advances the feed', (
    tester,
  ) async {
    var finished = 0;
    await pumpPlayer(
      tester,
      current: false,
      active: false,
      onFinished: () => finished++,
    );
    await initializePlayers(tester);
    platform.complete(platform.players.keys.single);
    await tester.pump();
    await tester.pump();
    expect(finished, 0);
    expect(platform.players.values.single.playCount, 0);
    await removePlayers(tester);
  });

  testWidgets('disposal before initialization ignores late platform events', (
    tester,
  ) async {
    var finished = 0;
    await pumpPlayer(tester, onFinished: () => finished++);
    expect(platform.players, hasLength(1));
    final id = platform.players.keys.single;
    await removePlayers(tester);

    platform.initialize(id);
    platform.complete(id);
    await tester.pump();
    expect(finished, 0);
    expect(platform.players[id]!.playCount, 0);
    expect(tester.takeException(), isNull);
  });
}

class _Player {
  _Player(this.asset);

  final String asset;
  final events = StreamController<VideoEvent>();
  bool playing = false;
  bool looping = false;
  double volume = 1;
  int playCount = 0;
  int pauseCount = 0;
  Duration position = Duration.zero;
  final seeks = <Duration>[];
}

class _VideoPlatform extends VideoPlayerPlatform {
  final players = <int, _Player>{};
  final disposedIds = <int>{};

  Set<int> get playingIds => players.entries
      .where((entry) => entry.value.playing)
      .map((entry) => entry.key)
      .toSet();

  int idFor(String name) => players.entries
      .singleWhere((entry) => entry.value.asset == 'assets/videos/$name.mp4')
      .key;

  void initialize(int id) => players[id]!.events.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: _duration,
      size: const Size(720, 1280),
    ),
  );

  void complete(int id) =>
      players[id]!.events.add(VideoEvent(eventType: VideoEventType.completed));

  Future<void> closeStreams() async {
    for (final player in players.values) {
      await player.events.close();
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = players.length;
    players[id] = _Player(options.dataSource.asset!);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      players[playerId]!.events.stream;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {
    disposedIds.add(playerId);
    players[playerId]!.playing = false;
  }

  @override
  Future<void> play(int playerId) async {
    final player = players[playerId]!;
    player.playCount++;
    player.playing = true;
  }

  @override
  Future<void> pause(int playerId) async {
    final player = players[playerId]!;
    player.pauseCount++;
    player.playing = false;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final player = players[playerId]!;
    player.position = position;
    player.seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      players[playerId]!.position;

  @override
  Future<void> setVolume(int playerId, double volume) async {
    players[playerId]!.volume = volume;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    players[playerId]!.looping = looping;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
}
