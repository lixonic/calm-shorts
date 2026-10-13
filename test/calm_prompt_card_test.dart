import 'dart:async';

import 'package:calm_reels/src/activity_sound.dart';
import 'package:calm_reels/src/calm_prompt_card.dart';
import 'package:calm_reels/src/calm_prompts.dart';
import 'package:calm_reels/src/session_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sound extends ActivitySound {
  final List<String> assets = [];
  var stops = 0;
  Completer<void>? pending;

  @override
  Future<void> play(String asset) {
    assets.add(asset);
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }
}

void main() {
  testWidgets('an unfinished count never blocks continuing', (tester) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CalmPromptCard(
          item: const PromptFeedItem(
            CalmPrompt(
              id: 'leaves',
              line: 'Count the leaves.',
              activity: PromptActivity.leaves,
            ),
            count: 2,
          ),
          onContinue: () => continued++,
        ),
      ),
    );
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.text('2 leaves. Take your time.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(continued, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('memory cues hide only when tapped and can be shown again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalmPromptCard(
          item: const PromptFeedItem(
            CalmPrompt(
              id: 'memory',
              line: 'Remember the leaves.',
              activity: PromptActivity.memory,
            ),
            count: 3,
          ),
          onContinue: () {},
        ),
      ),
    );
    expect(find.text('Hide leaves'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Hide leaves'), findsOneWidget);
    await tester.tap(find.text('Hide leaves'));
    await tester.pump();
    expect(find.text('The leaves are resting.'), findsOneWidget);
    await tester.tap(find.text('Show leaves'));
    await tester.pump();
    expect(find.text('The leaves are resting.'), findsNothing);
    await tester.tap(find.text('Show me'));
    await tester.pump();
    expect(find.text('3 leaves. Take your time.'), findsOneWidget);
  });

  testWidgets('listening is opt-in and stops on navigation or backgrounding', (
    tester,
  ) async {
    final sound = _Sound();
    var active = true;
    var continued = 0;
    Widget card() => MaterialApp(
      home: CalmPromptCard(
        key: const ValueKey('voice'),
        item: const PromptFeedItem(
          CalmPrompt(
            id: 'voice',
            line: 'Count the hellos.',
            activity: PromptActivity.voices,
          ),
          count: 4,
        ),
        active: active,
        sound: sound,
        onContinue: () => continued++,
      ),
    );
    await tester.pumpWidget(card());
    expect(sound.assets, isEmpty);
    await tester.tap(find.text('Listen'));
    await tester.pump();
    expect(sound.assets, ['assets/activities/voices-4.m4a']);
    expect(find.text('Stop'), findsOneWidget);
    active = false;
    await tester.pumpWidget(card());
    await tester.pump();
    expect(sound.stops, 1);
    active = true;
    await tester.pumpWidget(card());
    expect(sound.assets, hasLength(1));
    await tester.tap(find.text('Listen'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(continued, 1);
    expect(sound.stops, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(sound.stops, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Continue stays available on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: CalmPromptCard(
            item: const PromptFeedItem(
              CalmPrompt(
                id: 'hand',
                line: 'How many fingers are held up?',
                activity: PromptActivity.fingers,
              ),
              count: 5,
            ),
            onContinue: () => continued++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Continue'));
    expect(continued, 1);
    expect(tester.takeException(), isNull);
  });
}
