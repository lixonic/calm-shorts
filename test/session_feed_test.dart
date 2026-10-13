import 'dart:math';

import 'package:calm_reels/src/calm_prompts.dart';
import 'package:calm_reels/src/session_feed.dart';
import 'package:calm_reels/src/video_library.dart';
import 'package:flutter_test/flutter_test.dart';

VideoClip _clip(String id) => VideoClip(
  id: id,
  assetPath: 'assets/videos/$id.mp4',
  title: id,
  aspectRatio: 9 / 16,
  durationSeconds: 8,
  hasAudio: true,
);

List<CalmPrompt> _prompts(int count) => List.generate(
  count,
  (index) => CalmPrompt(id: 'p$index', line: 'Prompt $index'),
);

void main() {
  test('Every video appears exactly once in a session', () {
    final pool = List.generate(302, (index) => _clip('video-$index'));
    final feed = SessionFeed(pool, random: Random(42), prompts: _prompts(50));
    final videos = [
      for (var index = 0; index < feed.length; index++)
        if (feed.at(index) case VideoFeedItem(:final clip)) clip.id,
    ];
    expect(videos.toSet(), pool.map((clip) => clip.id).toSet());
    expect(videos.length, pool.length);
  });

  test('A prompt appears after every five videos', () {
    final pool = List.generate(12, (index) => _clip('video-$index'));
    final feed = SessionFeed(
      pool,
      random: Random(7),
      prompts: _prompts(50),
      promptEvery: 5,
    );
    final kinds = [
      for (var index = 0; index < feed.length; index++)
        feed.at(index) is PromptFeedItem ? 'p' : 'v',
    ];
    expect(kinds.join(), 'vvvvvpvvvvvpvv');
  });

  test('The first fifty prompts are unique and drawn from the full set', () {
    final prompts = _prompts(50);
    final pool = List.generate(250, (index) => _clip('video-$index'));
    final feed = SessionFeed(pool, random: Random(3), prompts: prompts);
    final shown = [
      for (var index = 0; index < feed.length; index++)
        if (feed.at(index) case PromptFeedItem(:final prompt)) prompt.id,
    ];
    expect(shown, hasLength(50));
    expect(shown.toSet(), prompts.map((prompt) => prompt.id).toSet());
  });

  test('Prompts recycle only after the full bag is used', () {
    final pool = List.generate(25, (index) => _clip('video-$index'));
    final prompts = _prompts(3);
    final feed = SessionFeed(pool, random: Random(11), prompts: prompts);
    final shown = [
      for (var index = 0; index < feed.length; index++)
        if (feed.at(index) case PromptFeedItem(:final prompt)) prompt.id,
    ];
    expect(shown, hasLength(5));
    expect(shown.take(3).toSet(), prompts.map((prompt) => prompt.id).toSet());
    expect(shown[3], isNot(shown[2]));
  });

  test('Back navigation never changes the session order', () {
    final feed = SessionFeed(
      [_clip('a'), _clip('b'), _clip('c'), _clip('d'), _clip('e'), _clip('f')],
      random: Random(8),
      prompts: _prompts(4),
    );
    final original = List.generate(feed.length, feed.at);
    for (final index in [5, 1, 0, 4, 2, 3]) {
      expect(identical(feed.at(index), original[index]), isTrue);
    }
    expect(feed.length, 7);
  });

  test(
    'All card colors are distinct and counting cues stay stable in history',
    () {
      final feed = SessionFeed(
        List.generate(334, (index) => _clip('video-$index')),
        prompts: const [
          CalmPrompt(
            id: 'voice',
            line: 'Count the hellos.',
            activity: PromptActivity.voices,
          ),
        ],
        random: Random(21),
      );
      final moments = [
        for (var index = 0; index < feed.length; index++)
          if (feed.at(index) case final PromptFeedItem item) item,
      ];
      expect(moments, hasLength(66));
      final colors = moments.expand((item) => item.colors).toList();
      expect(colors.toSet(), hasLength(colors.length));
      for (final moment in moments) {
        expect(moment.count, inInclusiveRange(1, 5));
        expect(
          moment.soundAsset,
          'assets/activities/voices-${moment.count}.m4a',
        );
      }
      final again = feed.at(5) as PromptFeedItem;
      expect(identical(again, moments.first), isTrue);
      expect(again.colors, moments.first.colors);
      expect(again.count, moments.first.count);
    },
  );

  test('Empty pools and duplicate videos are rejected', () {
    expect(() => SessionFeed(const []), throwsArgumentError);
    expect(() => SessionFeed([_clip('a'), _clip('a')]), throwsArgumentError);
  });

  test('Removing all prompts leaves a video-only feed', () {
    final feed = SessionFeed([_clip('a'), _clip('b')], promptEvery: 1);
    expect(feed.length, 2);
    expect(feed.at(0), isA<VideoFeedItem>());
    expect(feed.at(1), isA<VideoFeedItem>());
  });

  test('A custom prompt interval is respected', () {
    final feed = SessionFeed(
      [_clip('a'), _clip('b'), _clip('c')],
      prompts: _prompts(1),
      promptEvery: 2,
    );
    expect(feed.length, 4);
    expect(feed.at(2), isA<PromptFeedItem>());
    expect(feed.at(3), isA<VideoFeedItem>());
  });
}
