import 'dart:math';

import '../assistant/smart_queue.dart';
import '../music_profile/music_profile.dart';

/// Forma del viaje musical.
enum JourneyShape {
  /// Tranquilo → sube → pico → baja → relajado.
  arco,

  /// Tranquilo → cada vez con más energía.
  subida,

  /// De donde estés → cada vez más tranquilo (para descansar o dormir).
  bajada,
}

/// Un paso del viaje: energía objetivo y la canción elegida.
class JourneyStep {
  const JourneyStep(this.energy, this.query, {this.fromYourMusic = false, this.stage = ''});
  final int energy;
  final String query;

  /// Viene de tu música (si no, es una búsqueda del tipo de música).
  final bool fromYourMusic;
  final String stage;
}

class Journey {
  const Journey(this.shape, this.minutes, this.steps);
  final JourneyShape shape;
  final int minutes;
  final List<JourneyStep> steps;

  int get fromYours => steps.where((s) => s.fromYourMusic).length;

  static String nameOf(JourneyShape s) => switch (s) {
        JourneyShape.arco => 'Arco',
        JourneyShape.subida => 'Subida',
        JourneyShape.bajada => 'Bajada',
      };

  String get description => switch (shape) {
        JourneyShape.arco => 'Empieza tranquilo, sube hasta el pico y termina relajado.',
        JourneyShape.subida => 'Empieza tranquilo y la energía sube poco a poco.',
        JourneyShape.bajada => 'La energía baja poco a poco hasta quedar en calma.',
      };
}

/// Arma viajes musicales con progresión de energía (0 = para dormir, 5 = para
/// entrenar). La energía sale de tus listas por ambiente y del nombre de la
/// canción: **no** se analiza el audio. Si para un tramo no hay canciones
/// tuyas, usa una búsqueda de ese tipo de música (y lo dice).
class JourneyPlanner {
  /// Minutos por canción en promedio.
  static const songMinutes = 3.5;

  /// Búsquedas por energía (varias, para no repetir la misma canción).
  static const _fallback = <int, List<String>>{
    0: ['musica para dormir', 'piano relajante para dormir', 'sonidos suaves para dormir'],
    1: ['musica tranquila relajante', 'acustico relajante', 'chill en español'],
    2: ['musica suave acustica', 'baladas pop suaves', 'pop tranquilo en español'],
    3: ['musica alegre', 'pop alegre en español', 'exitos alegres'],
    4: ['musica para bailar', 'reggaeton para bailar exitos', 'dance pop exitos'],
    5: ['musica con energia para entrenar', 'musica para gimnasio', 'electronica con energia'],
  };

  static const _stageNames = <int, String>{
    0: 'calma', 1: 'tranquilo', 2: 'suave', 3: 'animado', 4: 'con energía', 5: 'pico',
  };

  /// Curva de energía para [n] canciones.
  static List<int> curve(JourneyShape shape, int n, {int start = 1, int peak = 5}) {
    if (n <= 0) return const [];
    if (n == 1) return [shape == JourneyShape.bajada ? 0 : peak];
    return [
      for (var i = 0; i < n; i++)
        () {
          final x = i / (n - 1); // 0 → 1
          final v = switch (shape) {
            JourneyShape.subida => start + (peak - start) * x,
            JourneyShape.bajada => start + (0 - start) * x,
            // Seno: sube hasta el pico (algo antes de la mitad) y baja hasta el inicio.
            JourneyShape.arco => 1 + (peak - 1) * sin(pi * pow(x, 0.85)),
          };
          return v.round().clamp(0, 5);
        }(),
    ];
  }

  /// Arma el viaje. [startEnergy]: lo que suena (para «bajada»).
  static Journey plan(MusicProfile profile, JourneyShape shape,
      {int minutes = 45, int? startEnergy, Random? random, Set<String> blocked = const {}, Set<String> avoid = const {}}) {
    final n = (minutes / songMinutes).round().clamp(4, 40);
    final targets = curve(shape, n, start: shape == JourneyShape.bajada ? (startEnergy ?? 3).clamp(1, 5) : 1);
    final rnd = random ?? Random();

    final moodOf = <String, String>{};
    for (final e in profile.moodTracks.entries) {
      for (final k in e.value) {
        moodOf[k] ??= e.key;
      }
    }
    final byEnergy = <int, List<TrackStats>>{};
    for (final t in profile.tracks.values) {
      if (t.dislikes > t.likes || t.skips > t.completes + 2) continue;
      if (blocked.contains((t.artist ?? '').toLowerCase().trim())) continue;
      if (avoid.contains(t.key)) continue; // se está repitiendo o suena ahora
      final e = SmartQueue.moodEnergy[moodOf[t.key]] ?? SmartQueue.energyFromWords('${t.title} ${t.artist ?? ''}');
      if (e == null) continue;
      (byEnergy[e] ??= []).add(t);
    }
    for (final l in byEnergy.values) {
      l.shuffle(rnd);
      l.sort((a, b) => (b.completes + b.likes * 2).compareTo(a.completes + a.likes * 2));
    }

    final used = <String>{};
    final fallbackUses = <int, int>{};
    String? lastArtist;
    final steps = <JourneyStep>[];
    for (final target in targets) {
      TrackStats? pick;
      // Primero la energía exacta, luego ±1.
      for (final e in [target, target - 1, target + 1]) {
        final list = byEnergy[e];
        if (list == null) continue;
        pick = list.where((t) => !used.contains(t.key) && (t.artist ?? '') != lastArtist).firstOrNull ??
            list.where((t) => !used.contains(t.key)).firstOrNull;
        if (pick != null) break;
      }
      if (pick != null) {
        used.add(pick.key);
        lastArtist = pick.artist;
        steps.add(JourneyStep(target, [pick.title, if (pick.artist != null) pick.artist].join(' '),
            fromYourMusic: true, stage: _stageNames[target]!));
      } else {
        lastArtist = null;
        final options = _fallback[target]!;
        final i = fallbackUses[target] = (fallbackUses[target] ?? -1) + 1;
        steps.add(JourneyStep(target, options[i % options.length], stage: _stageNames[target]!));
      }
    }
    return Journey(shape, minutes, steps);
  }
}
