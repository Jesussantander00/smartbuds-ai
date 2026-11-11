import 'dart:async';
import 'dart:convert';
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

/// Cuándo sueles escuchar música.
class ListeningPattern {
  const ListeningPattern({
    required this.sessions,
    this.weekdayStart,
    this.weekendStart,
    this.typicalEnd,
  });
  final int sessions;
  final int? weekdayStart;
  final int? weekendStart;
  final int? typicalEnd;

  static String hour(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'a. m.' : 'p. m.'}';
  }

  bool get isEmpty => weekdayStart == null && weekendStart == null && typicalEnd == null;
}

/// Cambios recientes en tu gusto.
class TasteShift {
  const TasteShift(this.rising, this.fading);

  /// Artistas que estás escuchando mucho más que antes.
  final List<String> rising;

  /// Artistas que escuchabas mucho y ya casi no.
  final List<String> fading;

  bool get isEmpty => rising.isEmpty && fading.isEmpty;
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
  static const maxHistory = 15000; // ~un año de escucha, para «Tu año en música»

  final Map<String, TrackStats> tracks = {};
  final List<ListenEvent> history = [];

  /// Modo privado: mientras devuelva true, nada de lo que suena se aprende.
  bool Function()? isPrivate;

  /// Canciones bloqueadas («Nunca más esta»): no se eligen nunca.
  bool Function(String title, String? artist)? isBlocked;

  /// Listas automáticas por ambiente: «entrenar» → canciones que terminaste
  /// o marcaste «me gusta» mientras sonaba ese ambiente.
  final Map<String, Set<String>> moodTracks = {};

  /// Ambiente pedido hace poco («pon algo para entrenar»), para aprender la lista.
  String? currentMood;
  DateTime? _moodAt;

  void setMood(String mood) {
    currentMood = mood;
    _moodAt = _clock();
  }

  bool _excluded(TrackStats t) => isBlocked?.call(t.title, t.artist) ?? false;

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
    moodTracks.clear();
    for (final e in ((d['moods'] as Map?) ?? const {}).entries) {
      moodTracks[e.key as String] = {...(e.value as List).cast<String>()};
    }
    notifyListeners();
  }

  // ------------------------------------------------- Listas por ambiente

  /// Una canción de tu lista automática para [mood], o null si aún es corta.
  TrackStats? pickMood(String mood, {Random? random}) {
    final recent = recentKeys(10);
    final list = (moodTracks[mood] ?? const <String>{})
        .map((k) => tracks[k])
        .whereType<TrackStats>()
        .where((t) => t.score(weights) > 0 && !_excluded(t) && !recent.contains(t.key))
        .toList();
    if (list.length < 3) return null;
    return list[(random ?? Random()).nextInt(list.length)];
  }

  // ------------------------------------------------ Favoritas olvidadas

  /// Canciones que te encantaban y llevan [after] sin sonar.
  List<TrackStats> forgottenFavorites({Duration after = const Duration(days: 21)}) {
    final now = _clock();
    final list = tracks.values
        .where((t) =>
            t.score(weights) >= 4 &&
            !_excluded(t) &&
            (t.lastPlayedAt == null || now.difference(t.lastPlayedAt!) >= after))
        .toList()
      ..sort((a, b) => b.score(weights).compareTo(a.score(weights)));
    return list;
  }

  // ------------------------------------------------- Editar tus gustos

  /// «Me gusta» desde la lista (sin que esté sonando).
  void likeTrack(String key) {
    final t = tracks[key];
    if (t == null) return;
    t.likes++;
    _record(t, ListenEventType.like);
    notifyListeners();
  }

  /// Olvida una canción por completo.
  void removeTrack(String key) {
    if (tracks.remove(key) == null) return;
    history.removeWhere((e) => e.key == key);
    for (final s in moodTracks.values) {
      s.remove(key);
    }
    if (_current?.key == key) _current = null;
    _scheduleSave();
    notifyListeners();
  }

  // --------------------------------------------- Copia y comparar gustos

  /// Copia de seguridad de tus gustos (JSON) para guardar o pasar a otro teléfono.
  /// Solo canciones y listas (sin el historial detallado) para que quepa en un mensaje.
  String exportJson() => jsonEncode({
        'app': 'smartbuds',
        'v': 1,
        'tracks': [for (final t in tracks.values) t.toJson()],
        'moods': {for (final e in moodTracks.entries) e.key: e.value.toList()},
      });

  /// Une una copia exportada con lo que ya hay. Devuelve cuántas canciones trajo,
  /// o -1 si el texto no es una copia válida.
  int importJson(String raw) {
    try {
      final d = jsonDecode(raw.trim());
      if (d is! Map || d['tracks'] is! List) return -1;
      final list = [
        for (final t in d['tracks'] as List)
          TrackStats.fromJson(Map<String, dynamic>.from(t as Map)),
      ];
      mergeRemote(list);
      for (final e in ((d['moods'] as Map?) ?? const {}).entries) {
        (moodTracks[e.key as String] ??= <String>{}).addAll((e.value as List).cast<String>());
      }
      _scheduleSave();
      return list.length;
    } catch (_) {
      return -1;
    }
  }

  /// Código corto con tus 15 artistas principales, para comparar con amigos.
  String tasteCode() {
    final names = topArtists(15).map((e) => e.$1).toList();
    return 'SB1:${base64Url.encode(utf8.encode(jsonEncode(names)))}';
  }

  /// Compara tu gusto con el código de otra persona.
  /// Devuelve el % de afinidad y los artistas en común, o null si el código no sirve.
  ({int percent, List<String> shared})? compareTaste(String code) {
    final raw = code.trim();
    final i = raw.indexOf('SB1:');
    if (i < 0) return null;
    try {
      final payload = raw.substring(i + 4).split(RegExp(r'\s')).first;
      final theirs = (jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))))
              as List)
          .cast<String>();
      final mine = topArtists(15).map((e) => e.$1).toList();
      if (theirs.isEmpty || mine.isEmpty) return (percent: 0, shared: <String>[]);
      final mineLow = {for (final m in mine) m.toLowerCase(): m};
      final shared = [
        for (final t in theirs)
          if (mineLow.containsKey(t.toLowerCase())) mineLow[t.toLowerCase()]!,
      ];
      final union = {...mineLow.keys, ...theirs.map((t) => t.toLowerCase())}.length;
      // Jaccard suavizado: compartir 5 de 15 ya es mucha afinidad.
      final pct = (100 * (shared.length / union) * 2.2).clamp(0, 100).round();
      return (percent: pct, shared: shared);
    } catch (_) {
      return null;
    }
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
    if (isPrivate?.call() ?? false) {
      _current = null; // al salir del modo privado no se le acredita nada
      return;
    }
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
    final tired = {for (final (t, _) in overexposed()) t.key}; // descanso para las sobreexpuestas
    final candidates = topTracks(30)
        .where((t) =>
            t.key != _current?.key && !recent.contains(t.key) && !_excluded(t) && !tired.contains(t.key))
        .toList()
      // Favoritas de este momento del día primero (hasta +50 % de puntuación).
      ..sort((a, b) => (b.score(weights) * (1 + 0.5 * b.affinity(now)))
          .compareTo(a.score(weights) * (1 + 0.5 * a.affinity(now))));
    if (candidates.isEmpty) return null;
    final top = candidates.take(5).toList();
    return top[(random ?? Random()).nextInt(top.length)];
  }

  // ================================================ Inteligencia musical

  /// Reproducciones por artista entre [from] y [to] (desde el historial).
  Map<String, int> _artistPlays(DateTime from, DateTime to) {
    final out = <String, int>{};
    for (final e in history) {
      if (e.type != ListenEventType.play || e.at.isBefore(from) || !e.at.isBefore(to)) continue;
      final a = tracks[e.key]?.artist;
      if (a == null || a.isEmpty) continue;
      out[a] = (out[a] ?? 0) + 1;
    }
    return out;
  }

  /// Detector de cambios de gusto: artistas que están creciendo en las últimas
  /// 2 semanas frente a los 2 meses anteriores (y los que dejaste de escuchar).
  TasteShift tasteShift() {
    final now = _clock();
    final recent = _artistPlays(now.subtract(const Duration(days: 14)), now.add(const Duration(seconds: 1)));
    final before = _artistPlays(now.subtract(const Duration(days: 74)), now.subtract(const Duration(days: 14)));
    final rTotal = recent.values.fold<int>(0, (a, b) => a + b);
    final bTotal = before.values.fold<int>(0, (a, b) => a + b);
    if (rTotal < 8) return const TasteShift([], []);
    double share(Map<String, int> m, int total, String a) => total == 0 ? 0 : (m[a] ?? 0) / total;
    final rising = <String>[];
    for (final a in recent.keys) {
      final now_ = share(recent, rTotal, a);
      final was = share(before, bTotal, a);
      if ((recent[a] ?? 0) >= 3 && now_ >= .12 && now_ >= was * 2 + .05) rising.add(a);
    }
    rising.sort((a, b) => (recent[b] ?? 0).compareTo(recent[a] ?? 0));
    final fading = <String>[];
    if (bTotal >= 15) {
      for (final a in before.keys) {
        if (share(before, bTotal, a) >= .15 && share(recent, rTotal, a) < .03) fading.add(a);
      }
    }
    return TasteShift(rising.take(3).toList(), fading.take(3).toList());
  }

  /// Canciones sobreexpuestas: sonaron [times] veces o más en los últimos 7 días.
  List<(TrackStats, int)> overexposed({int times = 8}) {
    final from = _clock().subtract(const Duration(days: 7));
    final counts = <String, int>{};
    for (final e in history) {
      if (e.type == ListenEventType.play && !e.at.isBefore(from)) {
        counts[e.key] = (counts[e.key] ?? 0) + 1;
      }
    }
    final list = [
      for (final e in counts.entries)
        if (e.value >= times && tracks[e.key] != null) (tracks[e.key]!, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  }

  /// Evolución: tu artista principal mes a mes (los últimos [months]).
  List<({DateTime month, String? artist, int plays})> evolution({int months = 6}) {
    final now = _clock();
    final out = <({DateTime month, String? artist, int plays})>[];
    for (var i = months - 1; i >= 0; i--) {
      final start = DateTime(now.year, now.month - i);
      final end = DateTime(now.year, now.month - i + 1);
      final m = _artistPlays(start, end);
      final total = m.values.fold<int>(0, (a, b) => a + b);
      String? top;
      var best = 0;
      m.forEach((a, n) {
        if (n > best) {
          best = n;
          top = a;
        }
      });
      out.add((month: start, artist: top, plays: total));
    }
    return out;
  }

  /// «ADN» de por qué te gusta una canción, con lo que SmartBuds sabe de verdad
  /// (tu forma de escucharla), no adivinando cómo suena.
  List<String> whyYouLike(String key) {
    final t = tracks[key];
    if (t == null) return const ['Es nueva para ti: SmartBuds aún no tiene datos de ella.'];
    final reasons = <String>[];
    if (t.likes > 0) reasons.add('Le diste «me gusta» ${t.likes == 1 ? 'una vez' : '${t.likes} veces'}.');
    if (t.plays >= 2) {
      final rate = t.plays == 0 ? 0 : (t.completes / t.plays * 100).round();
      reasons.add('La has puesto ${t.plays} veces y la escuchas completa el $rate %.');
    }
    if (t.repeats > 0) reasons.add('La repetiste ${t.repeats == 1 ? 'una vez' : '${t.repeats} veces'}.');
    final best = Daypart.values.reduce((a, b) => t.affinity(a) >= t.affinity(b) ? a : b);
    if (t.affinity(best) >= .5) reasons.add('Sobre todo te gusta ${best.label}.');
    final a = t.artist;
    if (a != null) {
      final rank = topArtists(10).indexWhere((e) => e.$1 == a);
      if (rank >= 0) reasons.add('$a es tu artista #${rank + 1}.');
    }
    for (final e in moodTracks.entries) {
      if (e.value.contains(key)) {
        reasons.add('Está en tu mezcla «${e.key}».');
        break;
      }
    }
    if (t.skips > t.completes && t.skips >= 2) reasons.add('Ojo: la saltas más de lo que la terminas.');
    return reasons.isEmpty ? const ['La has escuchado poco: SmartBuds sigue aprendiendo.'] : reasons;
  }

  // ================================================ Patrones de escucha

  /// Tus sesiones (reproducciones separadas por más de 30 min de silencio):
  /// a qué hora sueles empezar y terminar, entre semana y fin de semana.
  ListeningPattern pattern() {
    final plays = [
      for (final e in history)
        if (e.type == ListenEventType.play) e.at,
    ]..sort();
    final starts = <DateTime>[], ends = <DateTime>[];
    for (var i = 0; i < plays.length; i++) {
      if (i == 0 || plays[i].difference(plays[i - 1]) > const Duration(minutes: 30)) {
        starts.add(plays[i]);
        if (i > 0) ends.add(plays[i - 1]);
      }
    }
    if (plays.isNotEmpty) ends.add(plays.last);
    int? typicalHour(Iterable<DateTime> list) {
      final counts = List<int>.filled(24, 0);
      for (final d in list) {
        counts[d.hour]++;
      }
      var best = -1, bestN = 0;
      for (var h = 0; h < 24; h++) {
        if (counts[h] > bestN) {
          bestN = counts[h];
          best = h;
        }
      }
      return bestN >= 2 ? best : null;
    }

    bool weekend(DateTime d) => d.weekday >= DateTime.saturday;
    return ListeningPattern(
      sessions: starts.length,
      weekdayStart: typicalHour(starts.where((d) => !weekend(d))),
      weekendStart: typicalHour(starts.where(weekend)),
      typicalEnd: typicalHour(ends),
    );
  }

  /// ¿Es tu hora habitual de escuchar? (para la rutina de Inicio)
  bool isUsualListeningTime() {
    final p = pattern();
    final now = _clock();
    final h = now.weekday >= DateTime.saturday ? p.weekendStart : p.weekdayStart;
    return h != null && (now.hour == h || now.hour == (h + 23) % 24);
  }

  // ==================================================== Tus datos

  /// Borra lo que escuchaste entre [from] y [to] (y descuenta sus estadísticas).
  /// Devuelve cuántos registros quitó.
  int deleteRange(DateTime from, DateTime to) {
    var removed = 0;
    history.removeWhere((e) {
      if (e.at.isBefore(from) || !e.at.isBefore(to)) return false;
      final t = tracks[e.key];
      if (t != null) {
        switch (e.type) {
          case ListenEventType.play:
            t.plays = max(0, t.plays - 1);
          case ListenEventType.complete:
            t.completes = max(0, t.completes - 1);
          case ListenEventType.skip:
            t.skips = max(0, t.skips - 1);
          case ListenEventType.like:
            t.likes = max(0, t.likes - 1);
          case ListenEventType.dislike:
            t.dislikes = max(0, t.dislikes - 1);
          case ListenEventType.repeat:
            t.repeats = max(0, t.repeats - 1);
        }
        if (e.type == ListenEventType.complete ||
            e.type == ListenEventType.like ||
            e.type == ListenEventType.repeat) {
          final d = Daypart.of(e.at);
          t.positiveByDaypart[d] = max(0, (t.positiveByDaypart[d] ?? 0) - 1);
        }
      }
      removed++;
      return true;
    });
    tracks.removeWhere((k, t) => t.plays <= 0 && t.likes <= 0 && t.completes <= 0);
    if (removed > 0) {
      _current = null;
      _scheduleSave();
      notifyListeners();
    }
    return removed;
  }

  /// Tu historial en formato de tabla (CSV) para abrirlo en Excel o Sheets.
  String exportCsv({int maxRows = 3000}) {
    String esc(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    const names = {
      ListenEventType.play: 'reproducida',
      ListenEventType.complete: 'completa',
      ListenEventType.skip: 'saltada',
      ListenEventType.like: 'me gusta',
      ListenEventType.dislike: 'no me gusta',
      ListenEventType.repeat: 'repetida',
    };
    final rows = ['fecha,cancion,artista,evento'];
    for (final e in history.reversed.take(maxRows)) {
      final t = tracks[e.key];
      rows.add([
        e.at.toIso8601String().substring(0, 19).replaceFirst('T', ' '),
        esc(t?.title ?? e.key),
        esc(t?.artist),
        names[e.type],
      ].join(','));
    }
    return rows.join('\n');
  }

  // ============================================ Organización de tus listas

  /// Tus favoritas de ahora: con señales positivas en los últimos 30 días.
  List<TrackStats> currentFavorites([int n = 10]) {
    final from = _clock().subtract(const Duration(days: 30));
    final recentPositive = {
      for (final e in history)
        if (!e.at.isBefore(from) &&
            (e.type == ListenEventType.complete ||
                e.type == ListenEventType.like ||
                e.type == ListenEventType.repeat))
          e.key,
    };
    return topTracks(200).where((t) => recentPositive.contains(t.key)).take(n).toList();
  }

  /// Tus clásicos: te gustan mucho, pero no los has escuchado este mes.
  List<TrackStats> classics([int n = 10]) {
    final current = {for (final t in currentFavorites(200)) t.key};
    return topTracks(200).where((t) => !current.contains(t.key)).take(n).toList();
  }

  /// Título «limpio» para detectar la misma canción con nombres distintos
  /// («Tusa (Official Video)», «TUSA - Letra», «Tusa ft. Nicki Minaj»).
  static String cleanTitle(String title) {
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
    t = t.replaceAll(
        RegExp(r'\b(feat\.?|ft\.?|featuring)\b.*$'), ' ');
    t = t.replaceAll(
        RegExp(r'-\s*(official|oficial|video|audio|lyric|letra|visualizer|remaster).*$'), ' ');
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final b = StringBuffer();
    for (final ch in t.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Grupos de la misma canción guardada con nombres distintos.
  List<List<TrackStats>> duplicateGroups() {
    final groups = <String, List<TrackStats>>{};
    for (final t in tracks.values) {
      final artist = cleanTitle(t.artist ?? '').split(' ').firstOrNull ?? '';
      final k = '${cleanTitle(t.title)}|$artist';
      if (k.startsWith('|')) continue;
      (groups[k] ??= []).add(t);
    }
    return [for (final g in groups.values) if (g.length > 1) g];
  }

  /// Une los duplicados en la versión más escuchada. Devuelve cuántos quitó.
  int mergeDuplicates() {
    var removed = 0;
    for (final g in duplicateGroups()) {
      g.sort((a, b) => b.plays.compareTo(a.plays));
      final keep = g.first;
      for (final d in g.skip(1)) {
        keep
          ..plays += d.plays
          ..completes += d.completes
          ..skips += d.skips
          ..repeats += d.repeats
          ..likes += d.likes
          ..dislikes += d.dislikes;
        d.positiveByDaypart.forEach((k, v) {
          keep.positiveByDaypart[k] = (keep.positiveByDaypart[k] ?? 0) + v;
        });
        final dl = d.lastPlayedAt, kl = keep.lastPlayedAt;
        if (dl != null && (kl == null || dl.isAfter(kl))) keep.lastPlayedAt = dl;
        for (var i = 0; i < history.length; i++) {
          final e = history[i];
          if (e.key == d.key) history[i] = ListenEvent(e.at, keep.key, e.type);
        }
        for (final set in moodTracks.values) {
          if (set.remove(d.key)) set.add(keep.key);
        }
        tracks.remove(d.key);
        removed++;
      }
    }
    if (removed > 0) {
      _scheduleSave();
      notifyListeners();
    }
    return removed;
  }

  /// Canciones para llenar unos [minutes] (≈3,5 min cada una), sin repetir.
  List<TrackStats> playlistFor(int minutes, {Random? random}) {
    final count = (minutes / 3.5).round().clamp(2, 40);
    final pool = topTracks(80).where((t) => !_excluded(t)).toList()..shuffle(random ?? Random());
    final now = Daypart.of(_clock());
    pool.sort((a, b) => b.affinity(now).compareTo(a.affinity(now)));
    return pool.take(count).toList();
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
    moodTracks.clear();
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
      // Lista automática del ambiente pedido en la última hora y media.
      final mood = currentMood, at = _moodAt;
      if (mood != null && at != null && ev.at.difference(at) < const Duration(minutes: 90)) {
        (moodTracks[mood] ??= <String>{}).add(stats.key);
      }
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
        'moods': {for (final e in moodTracks.entries) e.key: e.value.toList()},
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
