import 'dart:convert';

import 'package:flutter/services.dart';

enum PromptActivity { notice, fingers, leaves, stars, voices, chimes, memory }

class CalmPrompt {
  const CalmPrompt({
    required this.id,
    required this.line,
    this.activity = PromptActivity.notice,
  });

  final String id;
  final String line;
  final PromptActivity activity;
}

class PromptLibrary {
  const PromptLibrary({required this.prompts, required this.promptEvery});

  final List<CalmPrompt> prompts;
  final int promptEvery;
}

Future<PromptLibrary> loadPromptLibrary({AssetBundle? bundle}) async {
  final text = await (bundle ?? rootBundle).loadString('assets/prompts.json');
  final json = jsonDecode(text) as Map<String, dynamic>;
  final interval = json['promptEvery'];
  final rows = json['prompts'];
  if (json['schemaVersion'] != 1 ||
      interval is! int ||
      interval < 1 ||
      interval > 100 ||
      rows is! List) {
    throw const FormatException('Invalid prompt library');
  }
  final ids = <String>{};
  final prompts = <CalmPrompt>[];
  for (final entry in rows) {
    if (entry is! Map) throw const FormatException('Invalid prompt');
    final id = entry['id'];
    final line = entry['line'];
    final kind = entry['activity'] ?? 'notice';
    if (id is! String ||
        id.isEmpty ||
        line is! String ||
        line.trim().isEmpty ||
        !ids.add(id)) {
      throw const FormatException('Invalid or duplicate prompt');
    }
    final activity = PromptActivity.values.where((value) => value.name == kind);
    if (activity.isEmpty) throw const FormatException('Unknown activity');
    prompts.add(CalmPrompt(id: id, line: line, activity: activity.single));
  }
  return PromptLibrary(
    prompts: List.unmodifiable(prompts),
    promptEvery: interval,
  );
}
