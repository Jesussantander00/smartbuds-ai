import '../music_profile/music_profile.dart';

/// Un mes de tu historia musical.
class MonthStat {
  MonthStat(this.month);
  final DateTime month;
  int plays = 0;
  Duration listened = Duration.zero;
  final Map<String, int> artistPlays = {};
  final Map<String, int> songPlays = {};

  /// Artistas que escuchaste por primera vez este mes.
  final List<String> newArtists = [];

  String? get topArtist => _top(artistPlays);
  String? get topSong => _top(songPlays);

  static String? _top(Map<String, int> m) {
    if (m.isEmpty) return null;
    return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }
}

/// Una etapa: meses seguidos con el mismo artista número 1.
typedef MusicStage = ({String artist, DateTime from, DateTime to, int months});

/// Memoria musical a largo plazo: cómo cambiaron tus gustos mes a mes.
/// Todo sale de tu historial en el teléfono (hasta ~un año).
class TasteEvolution {
  TasteEvolution._(this.months, this.stages, this.rising, this.fading, this.discovered, this.keeper);

  /// Meses del más antiguo al más reciente.
  final List<MonthStat> months;
  final List<MusicStage> stages;

  /// Artistas que ganaron o perdieron peso entre el primer y el último tercio.
  final List<String> rising, fading;

  /// Artistas descubiertos en el periodo y el que más se quedó.
  final int discovered;
  final String? keeper;

  static const monthNames = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  static String monthLabel(DateTime m) => '${monthNames[m.month - 1]} ${m.year}';

  static TasteEvolution from(MusicProfile profile, {DateTime? now, int maxMonths = 12}) {
    final today = now ?? DateTime.now();
    final since = DateTime(today.year, today.month - (maxMonths - 1));
    final byMonth = <DateTime, MonthStat>{};
    final firstSeen = <String, DateTime>{};
    final display = <String, String>{};
    final h = profile.history;
    for (var i = 0; i < h.length; i++) {
      final e = h[i];
      if (e.type != ListenEventType.play) continue;
      final t = profile.tracks[e.key];
      final artist = (t?.artist ?? '').trim();
      final key = artist.toLowerCase();
      if (artist.isNotEmpty) {
        display[key] ??= artist;
        final first = firstSeen[key];
        if (first == null || e.at.isBefore(first)) firstSeen[key] = e.at;
      }
      if (e.at.isBefore(since)) continue;
      final m = DateTime(e.at.year, e.at.month);
      final s = byMonth.putIfAbsent(m, () => MonthStat(m));
      s.plays++;
      if (artist.isNotEmpty) s.artistPlays[artist] = (s.artistPlays[artist] ?? 0) + 1;
      if (t != null) s.songPlays[t.title] = (s.songPlays[t.title] ?? 0) + 1;
      DateTime? next;
      for (var j = i + 1; j < h.length; j++) {
        if (h[j].type == ListenEventType.play) {
          next = h[j].at;
          break;
        }
      }
      var d = (next ?? e.at.add(const Duration(minutes: 3))).difference(e.at);
      if (d.isNegative) d = Duration.zero;
      if (d > const Duration(minutes: 8)) d = const Duration(minutes: 8);
      s.listened += d;
    }
    // Primer mes de cada artista (dentro del historial).
    var discovered = 0;
    firstSeen.forEach((k, at) {
      final m = DateTime(at.year, at.month);
      final s = byMonth[m];
      if (s == null) return;
      // El primer mes del historial no cuenta como «descubrimiento»: ahí empieza la memoria.
      if (byMonth.keys.reduce((a, b) => a.isBefore(b) ? a : b) == m) return;
      s.newArtists.add(display[k]!);
      discovered++;
    });
    final months = byMonth.values.toList()..sort((a, b) => a.month.compareTo(b.month));

    // Etapas: meses seguidos con el mismo número 1.
    final stages = <MusicStage>[];
    for (final m in months) {
      final top = m.topArtist;
      if (top == null) continue;
      if (stages.isNotEmpty && stages.last.artist == top) {
        final s = stages.removeLast();
        stages.add((artist: top, from: s.from, to: m.month, months: s.months + 1));
      } else {
        stages.add((artist: top, from: m.month, to: m.month, months: 1));
      }
    }

    // Primer tercio contra último tercio (por reproducciones).
    final rising = <String>[], fading = <String>[];
    if (months.length >= 3) {
      final third = (months.length / 3).ceil();
      Map<String, int> sum(Iterable<MonthStat> ms) {
        final out = <String, int>{};
        for (final m in ms) {
          m.artistPlays.forEach((a, n) => out[a] = (out[a] ?? 0) + n);
        }
        return out;
      }

      final early = sum(months.take(third)), late = sum(months.skip(months.length - third));
      final eT = early.values.fold<int>(0, (a, b) => a + b), lT = late.values.fold<int>(0, (a, b) => a + b);
      if (eT >= 10 && lT >= 10) {
        double sh(Map<String, int> m, int t, String a) => (m[a] ?? 0) / t;
        final all = {...early.keys, ...late.keys};
        final diff = {for (final a in all) a: sh(late, lT, a) - sh(early, eT, a)};
        final sorted = diff.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        rising.addAll(sorted.where((e) => e.value >= .08).take(3).map((e) => e.key));
        fading.addAll(sorted.reversed.where((e) => e.value <= -.08).take(3).map((e) => e.key));
      }
    }

    // El descubrimiento que más se quedó.
    String? keeper;
    var best = 0;
    for (final m in months) {
      for (final a in m.newArtists) {
        final total = months.fold<int>(0, (s, x) => s + (x.artistPlays[a] ?? 0));
        if (total > best) {
          best = total;
          keeper = a;
        }
      }
    }
    return TasteEvolution._(months, stages, rising, fading, discovered, best >= 3 ? keeper : null);
  }

  /// Para decirlo en voz alta. Solo hechos de tu historial.
  String summary() {
    if (months.isEmpty) return 'Todavía no tengo suficiente historial para ver cómo cambian tus gustos.';
    final parts = <String>[];
    if (months.length < 2) {
      parts.add('Llevo menos de dos meses conociéndote.');
    } else {
      parts.add('Te recuerdo desde ${monthLabel(months.first.month)}.');
    }
    if (rising.isNotEmpty) parts.add('Ahora escuchas más a ${rising.join(' y ')}.');
    if (fading.isNotEmpty) parts.add('Antes escuchabas más a ${fading.join(' y ')}.');
    if (stages.length >= 2) {
      parts.add('Tus etapas: ${stages.map((s) => s.artist).toSet().take(4).join(', ')}.');
    }
    if (discovered > 0) {
      parts.add('Descubriste $discovered ${discovered == 1 ? 'artista' : 'artistas'}'
          '${keeper == null ? '' : '; el que más se quedó fue $keeper'}.');
    }
    if (parts.length == 1 && months.length >= 2) parts.add('Tus gustos se han mantenido bastante estables.');
    return parts.join(' ');
  }
}
