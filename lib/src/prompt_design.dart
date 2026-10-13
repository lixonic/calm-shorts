import 'dart:math';

import 'package:flutter/painting.dart';

/// Each card receives three distinct colors. Colors are never reused within
/// a session, and the feed stores them so revisiting a card keeps its design.
class AuroraColors {
  AuroraColors(this.random);

  final Random random;
  final Set<int> _used = {};

  List<int> next() {
    final hue = 135 + random.nextDouble() * 165;
    return List.unmodifiable(
      List.generate(3, (index) {
        int color;
        do {
          final shifted =
              135 + (hue - 135 + index * 47 + random.nextDouble() * 12) % 165;
          color = HSLColor.fromAHSL(
            1,
            shifted,
            0.36 + random.nextDouble() * 0.16,
            0.10 + index * 0.085 + random.nextDouble() * 0.025,
          ).toColor().toARGB32();
        } while (!_used.add(color));
        return color;
      }),
    );
  }
}
