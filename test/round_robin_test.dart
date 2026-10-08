import 'dart:math';

import 'package:calm_reels/src/round_robin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Every video occurs exactly once in each shuffled round', () {
    final pool = List.generate(302, (index) => 'video-$index');
    final timeline = RoundRobinTimeline(pool, random: Random(42));
    for (var round = 0; round < 5; round++) {
      final draws = List.generate(
        pool.length,
        (index) => timeline.at(round * pool.length + index),
      );
      expect(draws.map((draw) => draw.item).toSet(), pool.toSet());
      expect(draws.map((draw) => draw.item).toSet().length, pool.length);
      expect(draws.every((draw) => draw.round == round + 1), isTrue);
      expect(draws.first.position, 1);
      expect(draws.last.position, pool.length);
    }
  });

  test('A round boundary never repeats its previous video', () {
    for (var seed = 0; seed < 100; seed++) {
      final timeline = RoundRobinTimeline(['a', 'b'], random: Random(seed));
      for (var boundary = 2; boundary < 40; boundary += 2) {
        expect(
          timeline.at(boundary).item,
          isNot(timeline.at(boundary - 1).item),
        );
      }
    }
  });

  test('Back navigation and prefetched pages do not change the queue', () {
    final timeline = RoundRobinTimeline(['a', 'b', 'c'], random: Random(8));
    final original = List.generate(8, timeline.at);
    for (final index in [6, 2, 0, 7, 4, 1, 3, 5]) {
      expect(identical(timeline.at(index), original[index]), isTrue);
    }
    expect(timeline.at(8).round, 3);
  });

  test('Aspect collections have independent queues', () {
    final portrait = RoundRobinTimeline(['p1', 'p2'], random: Random(4));
    final landscape = RoundRobinTimeline(['l1', 'l2'], random: Random(4));
    final firstPortrait = portrait.at(0);
    landscape.at(30);
    expect(identical(portrait.at(0), firstPortrait), isTrue);
    expect(portrait.at(1).round, 1);
    expect(portrait.at(2).round, 2);
  });

  test('A one-video collection keeps playing across rounds', () {
    final timeline = RoundRobinTimeline(['only']);
    expect(timeline.at(10).item, 'only');
    expect(timeline.at(10).round, 11);
    expect(timeline.at(10).position, 1);
  });

  test('Empty pools and duplicate pool entries are rejected', () {
    expect(() => RoundRobinTimeline<String>([]), throwsArgumentError);
    expect(() => RoundRobinTimeline(['a', 'a']), throwsArgumentError);
  });
}
