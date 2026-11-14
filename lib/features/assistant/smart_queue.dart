import '../../core/voice_engine/command_parser.dart';
import '../music_profile/music_profile.dart';

/// Una canción de la cola con lo que SmartBuds sabe de ella.
class QueueItem {
  const QueueItem(this.query, {this.energy, this.artist, this.mood});
  final String query;

  /// Energía estimada de 0 (para dormir) a 5 (para entrenar), o null si no se sabe.
  final int? energy;
  final String? artist;
  final String? mood;
}

/// Cola inteligente: reordena lo que sigue para que el ambiente cambie poco a
/// poco (sin pasar de algo para dormir a algo de fiesta) y sin repetir artista
/// seguido. **No analiza el audio**: la energía sale de tus listas por
/// ambiente y de palabras del nombre; lo desconocido se deja cerca de donde estaba.
class SmartQueue {
  /// Energía de cada ambiente de SmartBuds.
  static const moodEnergy = <String, int>{
    'para dormir': 0,
    'tranquila': 1,
    'para concentrarte': 1,
    'triste': 1,
    'nostálgica': 2,
    'romántica': 2,
    'de despecho': 2,
    'alegre': 3,
    'con energía': 4,
    'de fiesta': 4,
    'para entrenar': 5,
  };

  /// Palabras del nombre que sugieren energía.
  static const _words = <String, int>{
    'acustico': 1, 'acustica': 1, 'lento': 1, 'lenta': 1, 'slowed': 1, 'piano': 1, 'lofi': 1,
    'chill': 1, 'balada': 1, 'unplugged': 1, 'remix': 4, 'dance': 4, 'fiesta': 4, 'perreo': 4,
    'workout': 5, 'gym': 5, 'sped': 4, 'electro': 4, 'house': 4,
  };

  static int? energyFromWords(String text) {
    final words = CommandParser.normalize(text).split(' ');
    for (final w in words) {
      final e = _words[w];
      if (e != null) return e;
    }
    return null;
  }

  /// Junta lo que se sabe de cada canción (energía, artista) desde el perfil.
  static List<QueueItem> describe(List<String> queue, MusicProfile profile) {
    final byText = <String, TrackStats>{};
    for (final t in profile.tracks.values) {
      byText[CommandParser.normalize('${t.title} ${t.artist ?? ''}')] = t;
      byText[CommandParser.normalize(t.title)] ??= t;
    }
    final moodOf = <String, String>{};
    for (final e in profile.moodTracks.entries) {
      for (final k in e.value) {
        moodOf[k] ??= e.key;
      }
    }
    return [
      for (final q in queue)
        () {
          final t = byText[CommandParser.normalize(q)];
          final mood = t == null ? null : moodOf[t.key];
          return QueueItem(q,
              energy: moodEnergy[mood] ?? energyFromWords(q), artist: t?.artist, mood: mood);
        }(),
    ];
  }

  /// Orden suave: desde la energía actual, cada paso elige la canción más
  /// parecida, evitando el mismo artista dos veces seguidas. Estable: si nada
  /// se sabe, el orden no cambia.
  static List<QueueItem> arrange(List<QueueItem> items, {int? startEnergy}) {
    final left = [...items];
    final out = <QueueItem>[];
    // Sin dato de lo que suena, empieza por lo más tranquilo y sube.
    final knownEnergies = items.map((i) => i.energy).whereType<int>();
    var e = startEnergy ?? (knownEnergies.isEmpty ? null : knownEnergies.reduce((a, b) => a < b ? a : b));
    String? lastArtist;
    while (left.isNotEmpty) {
      var best = 0;
      var bestScore = double.infinity;
      for (var i = 0; i < left.length; i++) {
        final it = left[i];
        var score = (it.energy == null || e == null) ? 1.2 : (it.energy! - e).abs().toDouble();
        final a = it.artist?.toLowerCase();
        if (a != null && a.isNotEmpty && a == lastArtist) score += 2.5;
        score += i * 0.05; // a igualdad, conserva el orden que elegiste
        if (score < bestScore) {
          bestScore = score;
          best = i;
        }
      }
      final pick = left.removeAt(best);
      out.add(pick);
      e = pick.energy ?? e;
      lastArtist = pick.artist?.toLowerCase();
    }
    return out;
  }

  /// Saltos bruscos: cambios de energía de 3 o más entre canciones seguidas.
  static int abruptJumps(List<QueueItem> items, {int? startEnergy}) {
    var jumps = 0;
    var prev = startEnergy;
    for (final it in items) {
      final e = it.energy;
      if (e == null) continue;
      if (prev != null && (e - prev).abs() >= 3) jumps++;
      prev = e;
    }
    return jumps;
  }

  /// Cuántas canciones tienen energía conocida.
  static int known(List<QueueItem> items) => items.where((i) => i.energy != null).length;
}
