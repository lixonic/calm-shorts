import 'dart:convert';

import 'package:flutter/services.dart';

enum AspectGroup {
  portrait('Portrait'),
  landscape('Landscape');

  const AspectGroup(this.label);
  final String label;
}

class VideoClip {
  const VideoClip({
    required this.id,
    required this.assetPath,
    required this.title,
    required this.aspectRatio,
    required this.durationSeconds,
    required this.hasAudio,
    this.posterAssetPath,
  });

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final path = json['assetPath'] as String;
    final ratio = (json['aspectRatio'] as num).toDouble();
    if (id.isEmpty || !path.startsWith('assets/videos/') || ratio <= 0) {
      throw const FormatException('Invalid bundled video entry');
    }
    return VideoClip(
      id: id,
      assetPath: path,
      title: json['title'] as String? ?? 'A quiet moment',
      aspectRatio: ratio,
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      hasAudio: json['hasAudio'] as bool,
      posterAssetPath: json['posterAssetPath'] as String?,
    );
  }

  final String id;
  final String assetPath;
  final String title;
  final String? posterAssetPath;
  final double aspectRatio;
  final double durationSeconds;
  final bool hasAudio;

  AspectGroup get group =>
      aspectRatio < 1 ? AspectGroup.portrait : AspectGroup.landscape;
}

Future<List<VideoClip>> loadVideoLibrary({AssetBundle? bundle}) async {
  final text = await (bundle ?? rootBundle).loadString('assets/library.json');
  final json = jsonDecode(text) as Map<String, dynamic>;
  if (json['schemaVersion'] != 1) {
    throw const FormatException('Unsupported video library');
  }
  final clips = (json['videos'] as List<dynamic>)
      .map((entry) => VideoClip.fromJson(entry as Map<String, dynamic>))
      .toList(growable: false);
  if (clips.map((clip) => clip.id).toSet().length != clips.length) {
    throw const FormatException('Duplicate video IDs');
  }
  return List.unmodifiable(clips);
}
