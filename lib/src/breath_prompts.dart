import 'dart:convert';

import 'package:flutter/services.dart';

class BreathPrompt {
  const BreathPrompt({required this.id, required this.line});

  final String id;
  final String line;
}

class PromptLibrary {
  const PromptLibrary({required this.prompts, required this.promptEvery});

  final List<BreathPrompt> prompts;
  final int promptEvery;
}

Future<PromptLibrary> loadPromptLibrary({AssetBundle? bundle}) async {
  final text = await (bundle ?? rootBundle).loadString('assets/prompts.json');
  final json = jsonDecode(text) as Map<String, dynamic>;
  final interval = json['promptEvery'];
  if (json['schemaVersion'] != 1 || interval is! int || interval < 1) {
    throw const FormatException('Invalid prompt library');
  }
  final ids = <String>{};
  final prompts = <BreathPrompt>[];
  for (final entry in json['prompts'] as List<dynamic>) {
    final id = entry['id'] as String;
    final line = entry['line'] as String;
    if (id.isEmpty || line.trim().isEmpty || !ids.add(id)) {
      throw const FormatException('Invalid or duplicate prompt');
    }
    prompts.add(BreathPrompt(id: id, line: line));
  }
  return PromptLibrary(
    prompts: List.unmodifiable(prompts),
    promptEvery: interval,
  );
}
