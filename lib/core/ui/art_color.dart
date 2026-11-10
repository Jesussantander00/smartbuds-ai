import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Color principal de una carátula (promedio de los píxeles con color,
/// ignorando casi blancos y casi negros). Se guarda por canción.
class ArtColor {
  static final Map<int, Color?> _cache = {};

  static Future<Color?> of(Uint8List bytes) async {
    final key = Object.hashAll([bytes.length, bytes.isEmpty ? 0 : bytes[bytes.length ~/ 2]]);
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return _cache[key] = null;
      var r = 0, g = 0, b = 0, n = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final pr = data.getUint8(i), pg = data.getUint8(i + 1), pb = data.getUint8(i + 2);
        final max = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
        final min = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
        if (max < 30 || min > 225 || max - min < 18) continue; // sin color
        r += pr;
        g += pg;
        b += pb;
        n++;
      }
      if (n < 10) return _cache[key] = null;
      final c = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
      // Más vivo y con luz media para que se note sin cansar.
      final hsl = HSLColor.fromColor(c);
      return _cache[key] = hsl
          .withSaturation((hsl.saturation * 1.2).clamp(.35, .85))
          .withLightness(hsl.lightness.clamp(.45, .65))
          .toColor();
    } catch (_) {
      return _cache[key] = null;
    }
  }
}
