import 'dart:math';

/// «Solo mi voz»: compara la huella de voz de cada frase (vector del modelo de
/// hablante de Vosk) con la huella guardada al entrenar.
class SpeakerGuard {
  SpeakerGuard({this.voiceprint, this.enabled = false, this.threshold = 0.5});

  /// Huella promedio de tu voz (null = sin entrenar).
  List<double>? voiceprint;
  bool enabled;

  /// Similitud mínima (0 a 1) para aceptar una orden. Más alto = más estricto.
  double threshold;

  bool get trained => voiceprint != null && voiceprint!.isNotEmpty;

  /// ¿Se acepta la frase? Sin entrenar, sin activar o sin huella en la frase
  /// (frases muy cortas), se acepta para no bloquear al usuario.
  bool accepts(List<double>? sample) {
    if (!enabled || !trained || sample == null || sample.isEmpty) return true;
    return similarity(voiceprint!, sample) >= threshold;
  }

  static double similarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (sqrt(na) * sqrt(nb));
  }

  static List<double> average(List<List<double>> samples) {
    final n = samples.first.length;
    final out = List<double>.filled(n, 0);
    for (final s in samples) {
      for (var i = 0; i < n; i++) {
        out[i] += s[i] / samples.length;
      }
    }
    return out;
  }
}
