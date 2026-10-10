import 'dart:math';

import 'breath_prompts.dart';
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
  const PromptFeedItem(this.prompt);

  final BreathPrompt prompt;
}

/// One shuffled pass of videos. After every [promptEvery] clips, a prompt
/// is inserted. Videos never repeat. Prompts are drawn from a shuffled bag
/// and only reuse a line after all 50 have appeared.
class SessionFeed {
  SessionFeed(
    Iterable<VideoClip> videos, {
    List<BreathPrompt> prompts = breathPrompts,
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
    if (prompts.isEmpty) {
      throw ArgumentError.value(prompts, 'prompts', 'Need at least one prompt');
    }
    pool.shuffle(_random);
    final promptBag = _shuffledPrompts(prompts);
    var promptCursor = 0;
    BreathPrompt? lastPrompt;
    final items = <FeedItem>[];
    for (var index = 0; index < pool.length; index++) {
      items.add(
        VideoFeedItem(
          clip: pool[index],
          videoNumber: index + 1,
          videoCount: pool.length,
        ),
      );
      if ((index + 1) % promptEvery == 0) {
        if (promptCursor >= promptBag.length) {
          promptBag
            ..clear()
            ..addAll(_shuffledPrompts(prompts, avoidFirst: lastPrompt));
          promptCursor = 0;
        }
        lastPrompt = promptBag[promptCursor++];
        items.add(PromptFeedItem(lastPrompt));
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

  List<BreathPrompt> _shuffledPrompts(
    List<BreathPrompt> prompts, {
    BreathPrompt? avoidFirst,
  }) {
    final bag = List<BreathPrompt>.of(prompts)..shuffle(_random);
    if (bag.length > 1 && avoidFirst != null && bag.first.id == avoidFirst.id) {
      final swapIndex = 1 + _random.nextInt(bag.length - 1);
      final first = bag.first;
      bag[0] = bag[swapIndex];
      bag[swapIndex] = first;
    }
    return bag;
  }
}
