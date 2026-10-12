import 'dart:convert';
import 'dart:typed_data';

import 'package:calm_reels/src/breath_prompts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _PromptBundle extends CachingAssetBundle {
  _PromptBundle(this.data);
  final Map<String, dynamic> data;

  @override
  Future<ByteData> load(String key) async {
    expect(key, 'assets/prompts.json');
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Prompt text and spacing come from the editable asset', () async {
    final library = await loadPromptLibrary(
      bundle: _PromptBundle({
        'schemaVersion': 1,
        'promptEvery': 3,
        'prompts': [
          {'id': 'custom', 'line': 'Notice a leaf nearby.'},
        ],
      }),
    );
    expect(library.promptEvery, 3);
    expect(library.prompts.single.id, 'custom');
    expect(library.prompts.single.line, 'Notice a leaf nearby.');
  });

  test('An empty prompt collection disables prompts', () async {
    final library = await loadPromptLibrary(
      bundle: _PromptBundle({
        'schemaVersion': 1,
        'promptEvery': 5,
        'prompts': [],
      }),
    );
    expect(library.prompts, isEmpty);
  });

  test('Duplicate prompt IDs and invalid intervals are rejected', () async {
    for (final data in [
      {'schemaVersion': 1, 'promptEvery': 0, 'prompts': []},
      {
        'schemaVersion': 1,
        'promptEvery': 5,
        'prompts': [
          {'id': 'same', 'line': 'First'},
          {'id': 'same', 'line': 'Second'},
        ],
      },
    ]) {
      await expectLater(
        loadPromptLibrary(bundle: _PromptBundle(data)),
        throwsFormatException,
      );
    }
  });
}
