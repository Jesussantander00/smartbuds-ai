import 'dart:math';

import '../music_profile/music_profile.dart';

/// Un artista en tus estadísticas avanzadas.
class ArtistStat {
  ArtistStat(this.name);
  final String name;
  int plays = 0, completes = 0, skips = 0, likes = 0, songs = 0;
  Duration listened = Duration.zero;
  DateTime? firstHeard;

  /// % de canciones terminadas sobre las que empezaron y terminaron o saltaste.
  int get completionRate {
    final decided = completes + skips;
    return decided == 0 ? 0 : (completes / decided * 100).round();
  }
}

/// Estadísticas avanzadas calculadas en el teléfono con tu historial.
/// Límite honesto: las apps de música no comparten el género ni (casi nunca)
/// el álbum con otras apps, así que no se inventan.
class AdvancedStats {
  AdvancedStats._({
    required this.artists,
    required this.heat,
    required this.listened,
    required this.songs,
    required this.currentStreak,
    required this.bestStreak,
    required this.discoveries,
    required this.keepers,
    required this.topShare,
    required this.activeDays,
  });

  /// Artistas ordenados por tiempo escuchado.
  final List<ArtistStat> artists;

  /// Reproducciones por día de la semana (0 = lunes) y hora (0–23).
  final List<List<int>> heat;

  final Duration listened;
  final int songs;

  /// Días seguidos con música (hasta hoy o ayer) y la mejor racha.
  final int currentStreak, bestStreak;

  /// Artistas que escuchaste por primera vez en los últimos 30 días…
  final List<ArtistStat> discoveries;

  /// …y los que se quedaron (3+ reproducciones o un «me gusta»).
  final List<ArtistStat> keepers;

  /// % del tiempo que se lleva tu artista número 1.
  final int topShare;

  /// Días distintos con música.
  final int activeDays;

  int get discoveryRate => discoveries.isEmpty ? 0 : (keepers.length / discoveries.length * 100).round();

  /// Hora del día en que más escuchas.
  int get peakHour {
    var best = 0, bestCount = -1;
    for (var h = 0; h < 24; h++) {
      final c = heat.fold<int>(0, (a, row) => a + row[h]);
      if (c > bestCount) {
        best = h;
        bestCount = c;
      }
    }
    return best;
  }

  /// Tope de tiempo por canción (si no hay otro evento, no se cuenta más).
  static const perSongCap = Duration(minutes: 8);

  static AdvancedStats from(MusicProfile profile, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final byArtist = <String, ArtistStat>{};
    ArtistStat statFor(String? artist) {
      final name = (artist == null || artist.trim().isEmpty) ? 'Desconocido' : artist.trim();
      return byArtist.putIfAbsent(name.toLowerCase(), () => ArtistStat(name));
    }

    for (final t in profile.tracks.values) {
      final a = statFor(t.artist);
      a.plays += t.plays;
      a.completes += t.completes;
      a.skips += t.skips;
      a.likes += t.likes;
      a.songs++;
    }

    final heat = List.generate(7, (_) => List.filled(24, 0));
    final days = <DateTime>{};
    var total = Duration.zero;
    final h = profile.history;
    for (var i = 0; i < h.length; i++) {
      final e = h[i];
      if (e.type != ListenEventType.play) continue;
      final t = profile.tracks[e.key];
      final a = statFor(t?.artist);
      a.firstHeard = a.firstHeard == null || e.at.isBefore(a.firstHeard!) ? e.at : a.firstHeard;
      heat[e.at.weekday - 1][e.at.hour]++;
      days.add(DateTime(e.at.year, e.at.month, e.at.day));
      // Tiempo: hasta la siguiente canción (o evento), con tope.
      DateTime? next;
      for (var j = i + 1; j < h.length; j++) {
        if (h[j].type == ListenEventType.play) {
          next = h[j].at;
          break;
        }
      }
      var d = (next ?? e.at.add(const Duration(minutes: 3))).difference(e.at);
      if (d.isNegative) d = Duration.zero;
      if (d > perSongCap) d = perSongCap;
      a.listened += d;
      total += d;
    }

    final artists = byArtist.values.where((a) => a.plays > 0 || a.listened > Duration.zero).toList()
      ..sort((x, y) {
        final c = y.listened.compareTo(x.listened);
        return c != 0 ? c : y.plays.compareTo(x.plays);
      });

    // Rachas de días.
    final sorted = days.toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
      best = max(best, run);
      prev = d;
    }
    final day0 = DateTime(today.year, today.month, today.day);
    var current = 0;
    var cursor = days.contains(day0) ? day0 : day0.subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final since = today.subtract(const Duration(days: 30));
    final discoveries = artists.where((a) => a.firstHeard != null && a.firstHeard!.isAfter(since)).toList();
    final keepers = discoveries.where((a) => a.plays >= 3 || a.likes > 0).toList();
    final share = total == Duration.zero || artists.isEmpty
        ? 0
        : (artists.first.listened.inSeconds / total.inSeconds * 100).round();

    return AdvancedStats._(
      artists: artists,
      heat: heat,
      listened: total,
      songs: profile.tracks.length,
      currentStreak: current,
      bestStreak: best,
      discoveries: discoveries,
      keepers: keepers,
      topShare: share,
      activeDays: days.length,
    );
  }
}
