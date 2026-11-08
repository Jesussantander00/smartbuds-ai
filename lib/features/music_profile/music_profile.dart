import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/storage/json_store.dart';

/// Puntuaciones del documento de arquitectura (configurables).
class ScoreWeights {
  const ScoreWeights({
    this.complete = 2,
    this.repeat = 3,
    this.like = 5,
    this.skip = -2,
    this.dislike = -5,
  });
  final double complete, repeat, like, skip, dislike;
}

/// Lo que SmartBuds sabe de una canción.
class TrackStats {
  TrackStats({
    required this.key,
    required this.title,
    this.artist,
    this.packageName,
    this.plays = 0,
    this.completes = 0,
    this.skips = 0,
    this.repeats = 0,
    this.likes = 0,
    this.dislikes = 0,
    this.lastPlayedAt,
    Map<Daypart, int>? positiveByDaypart,
  }) : positiveByDaypart = positiveByDaypart ?? {};

  final String key;
  final String title;
  final String? artist;
  String? packageName;
  int plays, completes, skips, repeats, likes, dislikes;
  DateTime? lastPlayedAt;

  /// Señales positivas (completa, repetida, me gusta) por momento del día.
  final Map<Daypart, int> positiveByDaypart;

  /// Qué tanto encaja esta canción con un momento del día (0 a 1).
  double affinity(Daypart d) {
    final total = positiveByDaypart.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0;
    return (positiveByDaypart[d] ?? 0) / total;
  }

  double score(ScoreWeights w) =>
      completes * w.complete +
      repeats * w.repeat +
      likes * w.like +
      skips * w.skip +
      dislikes * w.dislike;

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'artist': artist,
        'packageName': packageName,
        'plays': plays,
        'completes': completes,
        'skips': skips,
        'repeats': repeats,
        'likes': likes,
        'dislikes': dislikes,
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'positiveByDaypart': {
          for (final e in positiveByDaypart.entries) e.key.name: e.value,
        },
      };

  factory TrackStats.fromJson(Map<String, dynamic> j) => TrackStats(
        key: j['key'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        packageName: j['packageName'] as String?,
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        completes: (j['completes'] as num?)?.toInt() ?? 0,
        skips: (j['skips'] as num?)?.toInt() ?? 0,
        repeats: (j['repeats'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        dislikes: (j['dislikes'] as num?)?.toInt() ?? 0,
        lastPlayedAt: DateTime.tryParse((j['lastPlayedAt'] as String?) ?? ''),
        positiveByDaypart: {
          for (final e in ((j['positiveByDaypart'] as Map?) ?? const {}).entries)
            if (Daypart.values.any((d) => d.name == e.key))
              Daypart.values.firstWhere((d) => d.name == e.key): (e.value as num).toInt(),
        },
      );
}

enum ListenEventType { play, complete, skip, repeat, like, dislike }

/// Momentos del día, para que «Pon algo que me guste» elija según la hora.
enum Daypart {
  madrugada('de madrugada'),
  manana('en la mañana'),
  tarde('en la tarde'),
  noche('en la noche');

  const Daypart(this.label);
  final String label;

  static Daypart of(DateTime t) => switch (t.hour) {
        < 6 => Daypart.madrugada,
        < 12 => Daypart.manana,
        < 19 => Daypart.tarde,
        _ => Daypart.noche,
      };
}

class ListenEvent {
  const ListenEvent(this.at, this.key, this.type);
  final DateTime at;
  final String key;
  final ListenEventType type;

  Map<String, dynamic> toJson() =>
      {'at': at.toIso8601String(), 'key': key, 'type': type.name};

  static ListenEvent? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse((j['at'] as String?) ?? '');
    final type = ListenEventType.values
        .where((t) => t.name == j['type'])
        .firstOrNull;
    if (at == null || type == null) return null;
    return ListenEvent(at, j['key'] as String, type);
  }
}

/// AI Music Brain (versión 1): aprende de cómo escuchas, sin importar en qué app.
///
/// - Escuchar una canción ≥ 90 s cuenta como completa (+2).
/// - Decir «Cambia» en los primeros 30 s cuenta como salto (−2).
/// - Volver a ponerla con «Devuelve» cuenta como repetición (+3).
/// - «Me gusta» (+5) y «No me gusta» (−5) por voz.
class MusicProfile extends ChangeNotifier {
  MusicProfile({
    JsonStore? store,
    this.weights = const ScoreWeights(),
    DateTime Function()? clock,
    this.onEvent,
  })  : _store = store ?? MemoryJsonStore(),
        _clock = clock ?? DateTime.now;

  final JsonStore _store;
  final ScoreWeights weights;
  final DateTime Function() _clock;

  /// Se llama con cada evento (p. ej. para sincronizar con Supabase).
  final void Function(ListenEvent event, TrackStats stats)? onEvent;

  static const completeAfter = Duration(seconds: 90);
  static const skipBefore = Duration(seconds: 30);
  static const commandWindow = Duration(seconds: 6);
  static const maxHistory = 3000; // ~varias semanas, para el resumen semanal

  final Map<String, TrackStats> tracks = {};
  final List<ListenEvent> history = [];

  TrackStats? _current;
  DateTime? _currentStart;
  MusicCommand? _lastCommand;
  DateTime? _lastCommandAt;
  Timer? _saveTimer;

  /// Canción sonando ahora (según el reproductor detectado).
  TrackStats? get current => _current;

  Future<void> load() async {
    final d = await _store.load();
    if (d == null) return;
    tracks.clear();
    history.clear();
    for (final t in (d['tracks'] as List?) ?? const []) {
      final stats = TrackStats.fromJson(Map<String, dynamic>.from(t as Map));
      tracks[stats.key] = stats;
    }
    for (final e in (d['history'] as List?) ?? const []) {
      final ev = ListenEvent.fromJson(Map<String, dynamic>.from(e as Map));
      if (ev != null) history.add(ev);
    }
    notifyListeners();
  }

  /// Une canciones traídas de la nube (otra instalación u otro teléfono).
  /// Para cada canción se queda con el número más alto de cada señal, así que
  /// unir dos veces lo mismo no duplica nada.
  void mergeRemote(Iterable<TrackStats> remote) {
    var changed = false;
    for (final r in remote) {
      final local = tracks[r.key];
      if (local == null) {
        tracks[r.key] = r;
        changed = true;
        continue;
      }
      int hi(int a, int b) => a > b ? a : b;
      final before = local.score(weights);
      local
        ..plays = hi(local.plays, r.plays)
        ..completes = hi(local.completes, r.completes)
        ..skips = hi(local.skips, r.skips)
        ..repeats = hi(local.repeats, r.repeats)
        ..likes = hi(local.likes, r.likes)
        ..dislikes = hi(local.dislikes, r.dislikes);
      final lp = local.lastPlayedAt, rp = r.lastPlayedAt;
      if (rp != null && (lp == null || rp.isAfter(lp))) local.lastPlayedAt = rp;
      if (local.score(weights) != before) changed = true;
    }
    if (!changed) return;
    _scheduleSave();
    notifyListeners();
  }

  /// Avisa qué orden dio el usuario (para distinguir saltos y repeticiones).
  void noteCommand(MusicCommand command) {
    _lastCommand = command;
    _lastCommandAt = _clock();
  }

  bool _recentCommand(MusicCommand c) =>
      _lastCommand == c &&
      _lastCommandAt != null &&
      _clock().difference(_lastCommandAt!) <= commandWindow;

  /// Llamado cada vez que cambia el estado del reproductor activo.
  void observe(PlayerStatus? status) {
    if (status == null || !status.isPlaying || (status.title ?? '').isEmpty) {
      return;
    }
    final key = keyFor(status.title!, status.artist);
    if (key == _current?.key) return;

    final now = _clock();
    final prev = _current;
    if (prev != null && _currentStart != null) {
      final listened = now.difference(_currentStart!);
      if (listened >= completeAfter) {
        prev.completes++;
        // Cuenta para el momento en que se escuchó, no cuando se cambió.
        _record(prev, ListenEventType.complete, daypartAt: _currentStart);
      } else if (listened < skipBefore && _recentCommand(MusicCommand.next)) {
        prev.skips++;
        _record(prev, ListenEventType.skip);
      }
    }

    final stats = tracks.putIfAbsent(
      key,
      () => TrackStats(key: key, title: status.title!, artist: status.artist),
    );
    stats.packageName = status.packageName;
    if (stats.plays > 0 && _recentCommand(MusicCommand.previous)) {
      stats.repeats++;
      _record(stats, ListenEventType.repeat);
    }
    stats.plays++;
    stats.lastPlayedAt = now;
    _current = stats;
    _currentStart = now;
    _record(stats, ListenEventType.play);
    notifyListeners();
  }

  /// «Me gusta»: devuelve la canción marcada (o null si no suena nada).
  TrackStats? like() {
    final c = _current;
    if (c == null) return null;
    c.likes++;
    _record(c, ListenEventType.like);
    notifyListeners();
    return c;
  }

  /// «Repite»: la misma canción otra vez desde el principio (+3).
  TrackStats? markRepeat() {
    final c = _current;
    if (c == null) return null;
    c.repeats++;
    _record(c, ListenEventType.repeat);
    _currentStart = _clock(); // cuenta como escucha nueva
    notifyListeners();
    return c;
  }

  /// Saltadas seguidas al final del historial (para notar el aburrimiento).
  int recentSkipStreak({Duration within = const Duration(minutes: 5)}) {
    final now = _clock();
    var n = 0;
    for (final ev in history.reversed) {
      if (ev.type == ListenEventType.play) continue; // «sonó» no corta la racha
      if (ev.type != ListenEventType.skip || now.difference(ev.at) > within) break;
      n++;
    }
    return n;
  }

  /// Resumen de los últimos [days] días a partir del historial.
  WeekSummary summary({int days = 7}) {
    final now = _clock();
    final from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final perDay = List<int>.filled(days, 0);
    final perDaypart = {for (final d in Daypart.values) d: 0};
    final songCount = <String, int>{};
    var completes = 0;
    var plays = 0;
    for (final ev in history) {
      if (ev.at.isBefore(from)) continue;
      if (ev.type == ListenEventType.play) {
        plays++;
        final day = DateTime(ev.at.year, ev.at.month, ev.at.day).difference(from).inDays;
        if (day >= 0 && day < days) perDay[day]++;
        perDaypart[Daypart.of(ev.at)] = perDaypart[Daypart.of(ev.at)]! + 1;
        songCount[ev.key] = (songCount[ev.key] ?? 0) + 1;
      } else if (ev.type == ListenEventType.complete) {
        completes++;
      }
    }
    String? topKey;
    var best = 0;
    songCount.forEach((k, v) {
      if (v > best) {
        best = v;
        topKey = k;
      }
    });
    final artistCount = <String, int>{};
    songCount.forEach((k, v) {
      final a = tracks[k]?.artist;
      if (a != null && a.isNotEmpty) artistCount[a] = (artistCount[a] ?? 0) + v;
    });
    String? topArtist;
    best = 0;
    artistCount.forEach((a, v) {
      if (v > best) {
        best = v;
        topArtist = a;
      }
    });
    return WeekSummary(
      from: from,
      playsPerDay: perDay,
      playsPerDaypart: perDaypart,
      plays: plays,
      // Aproximado: ~3,5 min por canción completa y ~1 min por las demás.
      minutes: (completes * 3.5 + (plays - completes).clamp(0, plays) * 1.0).round(),
      topSong: topKey == null ? null : tracks[topKey],
      topArtist: topArtist,
    );
  }

  /// «No me gusta».
  TrackStats? dislike() {
    final c = _current;
    if (c == null) return null;
    c.dislikes++;
    _record(c, ListenEventType.dislike);
    notifyListeners();
    return c;
  }

  List<TrackStats> topTracks([int n = 10]) {
    final list = tracks.values.where((t) => t.score(weights) > 0).toList()
      ..sort((a, b) => b.score(weights).compareTo(a.score(weights)));
    return list.take(n).toList();
  }

  List<(String, double)> topArtists([int n = 5]) {
    final scores = <String, double>{};
    for (final t in tracks.values) {
      final a = t.artist;
      if (a == null || a.isEmpty) continue;
      scores[a] = (scores[a] ?? 0) + t.score(weights);
    }
    final list = scores.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list.take(n)) (e.key, e.value)];
  }

  /// «Pon algo que me guste»: una de tus mejores canciones que no haya
  /// sonado hace poco. Null si todavía no hay suficiente información.
  TrackStats? pickFavorite({Random? random}) {
    final recent = recentKeys(10);
    final now = Daypart.of(_clock());
    final candidates = topTracks(20)
        .where((t) => t.key != _current?.key && !recent.contains(t.key))
        .toList()
      // Favoritas de este momento del día primero (hasta +50 % de puntuación).
      ..sort((a, b) => (b.score(weights) * (1 + 0.5 * b.affinity(now)))
          .compareTo(a.score(weights) * (1 + 0.5 * a.affinity(now))));
    if (candidates.isEmpty) return null;
    final top = candidates.take(5).toList();
    return top[(random ?? Random()).nextInt(top.length)];
  }

  /// Canciones que sonaron hace poco (para no repetirlas).
  Set<String> recentKeys([int n = 10]) => history.reversed
      .where((e) => e.type == ListenEventType.play)
      .take(n)
      .map((e) => e.key)
      .toSet();

  /// ¿SmartBuds ya conoce esta canción?
  bool knows(String title, String? artist) => tracks.containsKey(keyFor(title, artist));

  /// Momento del día con más escucha positiva (para «Mi música»).
  Daypart? get favoriteDaypart {
    final totals = <Daypart, int>{};
    for (final t in tracks.values) {
      for (final e in t.positiveByDaypart.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
    }
    if (totals.isEmpty) return null;
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> clear() async {
    tracks.clear();
    history.clear();
    _current = null;
    _currentStart = null;
    await _store.save(_toJson());
    notifyListeners();
  }

  static String keyFor(String title, String? artist) =>
      '${title.trim().toLowerCase()}|${(artist ?? '').trim().toLowerCase()}';

  void _record(TrackStats stats, ListenEventType type, {DateTime? daypartAt}) {
    final ev = ListenEvent(_clock(), stats.key, type);
    if (type == ListenEventType.complete ||
        type == ListenEventType.repeat ||
        type == ListenEventType.like) {
      final d = Daypart.of(daypartAt ?? ev.at);
      stats.positiveByDaypart[d] = (stats.positiveByDaypart[d] ?? 0) + 1;
    }
    history.add(ev);
    if (history.length > maxHistory) history.removeRange(0, history.length - maxHistory);
    onEvent?.call(ev, stats);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => _store.save(_toJson()));
  }

  Map<String, dynamic> _toJson() => {
        'tracks': [for (final t in tracks.values) t.toJson()],
        'history': [for (final e in history) e.toJson()],
      };

  @override
  void dispose() {
    _saveTimer?.cancel();
    _store.save(_toJson());
    super.dispose();
  }
}

/// Resumen de escucha de la semana (para «Mi música»).
class WeekSummary {
  const WeekSummary({
    required this.from,
    required this.playsPerDay,
    required this.playsPerDaypart,
    required this.plays,
    required this.minutes,
    this.topSong,
    this.topArtist,
  });

  final DateTime from;
  final List<int> playsPerDay;
  final Map<Daypart, int> playsPerDaypart;
  final int plays;

  /// Minutos aproximados de escucha.
  final int minutes;
  final TrackStats? topSong;
  final String? topArtist;
}
