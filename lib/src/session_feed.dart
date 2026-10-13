import 'dart:math';

import 'calm_prompts.dart';
import 'prompt_design.dart';
import 'video_library.dart';

sealed class FeedItem {
  const FeedItem();
}

class VideoFeedItem extends FeedItem {
  const VideoFeedItem({
    required this.clip,
    required this.videoNumber,
    required this.videoCount,
  });

  final VideoClip clip;
  final int videoNumber;
  final int videoCount;
}

class PromptFeedItem extends FeedItem {
  const PromptFeedItem(
    this.prompt, {
    this.colors = const [0xff12282a, 0xff325f59, 0xff414f78],
    this.count = 3,
  });

  final CalmPrompt prompt;
  final List<int> colors;
  final int count;

  String? get soundAsset => switch (prompt.activity) {
    PromptActivity.voices || PromptActivity.chimes =>
      'assets/activities/${prompt.activity.name}-$count.m4a',
    _ => null,
  };
}

/// One shuffled pass of videos. After every [promptEvery] clips, a prompt
/// is inserted. Videos never repeat. Prompts are drawn from a shuffled bag
/// and only reuse a line after the entire prompt collection has appeared.
class SessionFeed {
  SessionFeed(
    Iterable<VideoClip> videos, {
    List<CalmPrompt> prompts = const [],
    Random? random,
    this.promptEvery = 5,
  }) : _random = random ?? Random() {
    if (promptEvery < 1) {
      throw ArgumentError.value(promptEvery, 'promptEvery');
    }
    final pool = List<VideoClip>.of(videos);
    if (pool.isEmpty) {
      throw ArgumentError.value(videos, 'videos', 'The pool cannot be empty');
    }
    final ids = pool.map((clip) => clip.id).toList();
    if (ids.toSet().length != ids.length) {
      throw ArgumentError.value(videos, 'videos', 'The pool must be unique');
    }
    pool.shuffle(_random);
    final promptBag = _shuffledPrompts(prompts);
    final aurora = AuroraColors(_random);
    var promptCursor = 0;
    CalmPrompt? lastPrompt;
    final items = <FeedItem>[];
    for (var index = 0; index < pool.length; index++) {
      items.add(
        VideoFeedItem(
          clip: pool[index],
          videoNumber: index + 1,
          videoCount: pool.length,
        ),
      );
      if (prompts.isNotEmpty && (index + 1) % promptEvery == 0) {
        if (promptCursor >= promptBag.length) {
          promptBag
            ..clear()
            ..addAll(_shuffledPrompts(prompts, avoidFirst: lastPrompt));
          promptCursor = 0;
        }
        lastPrompt = promptBag[promptCursor++];
        items.add(
          PromptFeedItem(
            lastPrompt,
            colors: aurora.next(),
            count: 1 + _random.nextInt(5),
          ),
        );
      }
    }
    _items = List.unmodifiable(items);
  }

  final Random _random;
  final int promptEvery;
  late final List<FeedItem> _items;

  int get length => _items.length;

  FeedItem at(int index) {
    if (index < 0 || index >= _items.length) {
      throw RangeError.index(index, _items);
    }
    return _items[index];
  }

  List<CalmPrompt> _shuffledPrompts(
    List<CalmPrompt> prompts, {
    CalmPrompt? avoidFirst,
  }) {
    final bag = List<CalmPrompt>.of(prompts)..shuffle(_random);
    if (bag.length > 1 && avoidFirst != null && bag.first.id == avoidFirst.id) {
      final swapIndex = 1 + _random.nextInt(bag.length - 1);
      final first = bag.first;
      bag[0] = bag[swapIndex];
      bag[swapIndex] = first;
    }
    return bag;
  }
}
