import 'dart:math';

import '../../connectors/deezer/similar_artists.dart';
import '../../core/settings/app_settings.dart';
import '../music_profile/music_profile.dart';

/// De dónde sale una recomendación (el cerebro aprende cuál funciona mejor contigo).
enum RecKind {
  /// Una de tus favoritas de siempre.
  favorite,

  /// Una favorita que hace rato no suena.
  rediscover,

  /// De un artista que estás escuchando cada vez más.
  rising,

  /// De tu mezcla para el ambiente pedido.
  mood,
}

/// Una canción recomendada, con su puntaje y el porqué en palabras.
class Recommendation {
  const Recommendation({
    required this.track,
    required this.kind,
    required this.score,
    required this.reasons,
  });

  final TrackStats track;
  final RecKind kind;
  final double score;
  final List<String> reasons;

  String get query => [track.title, if (track.artist != null) track.artist].join(' ');
}

/// Lo que el cerebro sabe del momento.
class BrainContext {
  const BrainContext({required this.now, this.mood, this.usageProfile, this.sessionSkips = 0});
  final DateTime now;

  /// Ambiente pedido hace poco («para entrenar», «tranquila»…).
  final String? mood;

  /// 'diario', 'estudio' o 'viaje'.
  final String? usageProfile;

  /// Cuántas canciones seguidas saltaste ahora (si saltas mucho, va a lo seguro).
  final int sessionSkips;
}

/// Qué hace buenas tus sesiones de música.
class SessionInsight {
  const SessionInsight({
    required this.sessions,
    required this.bestMinutes,
    required this.bestVariety,
    required this.bestCompletion,
    required this.summary,
  });

  final int sessions;

  /// Duración típica de tus mejores sesiones.
  final int bestMinutes;

  /// Artistas distintos por cada 10 canciones en tus mejores sesiones (0–10).
  final double bestVariety;

  /// % de canciones que terminas en tus mejores sesiones.
  final int bestCompletion;
  final String summary;
}

/// Cerebro musical adaptativo: une tus gustos, el momento del día, tus
/// mezclas, los artistas que van en ascenso, cómo vienen tus sesiones y lo que
/// pasó con sus recomendaciones anteriores, para decidir qué te pone.
///
/// Todo se calcula en el teléfono (Android e iPhone), sin permisos extra.
/// El radar usa Deezer (internet). Nunca reproduce nada sin que lo pidas.
class MusicBrain {
  MusicBrain({required this.profile, this.settings, this.similar, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final MusicProfile profile;
  final AppSettings? settings;
  final SimilarArtistsFinder? similar;
  final DateTime Function() _clock;

  /// Hora según el cerebro (inyectable en las pruebas).
  DateTime get now => _clock();

  // ----------------------------------------------------- Aprendizaje

  /// Peso de cada fuente (0,5 – 2). Sube cuando aciertas, baja cuando saltas.
  double weightOf(RecKind k) => settings?.brainWeights[k.name] ?? 1.0;

  /// Resultado de una recomendación: terminada / me gusta = acierto; saltada = fallo.
  void learn(RecKind kind, {required bool liked}) {
    final w = weightOf(kind);
    final next = (liked ? w * 1.08 : w * 0.92).clamp(0.5, 2.0).toDouble();
    settings?.setBrainWeight(kind.name, next);
  }

  // ------------------------------------------------ Datos suficientes

  /// Canciones escuchadas que hacen falta para recomendar con confianza.
  static const minPlays = 20;

  /// Cuánto sabe el cerebro de ti: canciones escuchadas (sin modo privado)
  /// y si todavía está aprendiendo. Con pocos datos lo dice en vez de inventar.
  ({int plays, int needed, bool learning}) readiness() {
    final plays = profile.tracks.values.fold<int>(0, (a, t) => a + t.plays);
    return (plays: plays, needed: minPlays, learning: plays < minPlays);
  }

  /// Puntaje de una canción para el cerebro. Un solo salto no la descarta:
  /// pudo ser el momento. Desde el segundo salto (o un «no me gusta») sí cuenta.
  double _score(TrackStats t) {
    final w = profile.weights;
    var v = t.score(w);
    if (t.skips == 1 && t.dislikes == 0) v -= w.skip; // perdona el primero
    return v;
  }

  // ---------------------------------------------------- Recomendar

  /// Las [n] canciones que más probablemente quieras escuchar ahora,
  /// con su porqué. Solo sugiere: reproducir lo decides tú.
  List<Recommendation> recommend(BrainContext ctx, {int n = 5}) {
    final now = ctx.now;
    final daypart = Daypart.of(now);
    final recent = profile.recentKeys(10);
    final tired = {for (final (t, _) in profile.overexposed()) t.key};
    final rising = profile.tasteShift().rising.map((a) => a.toLowerCase()).toSet();
    final moodSet = ctx.mood == null ? const <String>{} : (profile.moodTracks[ctx.mood] ?? const <String>{});
    final blocked = settings?.isBlocked;
    final pool = profile.tracks.values
        .where((t) =>
            _score(t) > 0 &&
            !recent.contains(t.key) &&
            !tired.contains(t.key) &&
            !(blocked?.call(t.title, t.artist) ?? false))
        .toList();
    if (pool.isEmpty) return const [];
    final maxScore = pool.map(_score).reduce(max);
    final careful = ctx.sessionSkips >= 2 || ctx.usageProfile == 'estudio';

    final scored = <Recommendation>[];
    for (final t in pool) {
      final reasons = <String>[];
      var kind = RecKind.favorite;
      // Cada razón sale de un dato real y lo muestra (veces, días, conteos).
      final base = _score(t) / maxScore; // 0–1
      var s = base;
      if (base > .6 && t.completes > 0) reasons.add('La terminaste ${t.completes} de ${t.plays} veces');

      final aff = t.affinity(daypart);
      s += aff * .6;
      final inDaypart = t.positiveByDaypart[daypart] ?? 0;
      if (aff >= .5 && inDaypart >= 2) reasons.add('La escuchaste $inDaypart veces ${daypart.label}');

      final completion = t.plays == 0 ? 0.0 : t.completes / t.plays;
      if (careful) {
        s += completion * .5 + (t.plays >= 3 ? .2 : 0);
        if (completion >= .8 && t.plays >= 3) {
          reasons.add('Casi siempre la escuchas completa (${t.completes} de ${t.plays})');
        }
      }

      final last = t.lastPlayedAt;
      if (last != null && now.difference(last) >= const Duration(days: 21) && base > .4) {
        s += .25;
        kind = RecKind.rediscover;
        reasons.add('Hace ${now.difference(last).inDays} días no suena');
      } else if (last != null && now.difference(last) < const Duration(hours: 2)) {
        s -= .4; // sonó hace muy poco
      }

      if (t.artist != null && rising.contains(t.artist!.toLowerCase())) {
        s += .3;
        kind = RecKind.rising;
        reasons.add('Escuchas más a ${t.artist} estas 2 semanas que antes');
      }

      if (moodSet.contains(t.key)) {
        s += .7;
        kind = RecKind.mood;
        reasons.add('Está en tu mezcla «${ctx.mood}»');
      }

      if (t.likes > 0) reasons.add('Le diste «me gusta»');
      s *= weightOf(kind);
      if (reasons.isEmpty) reasons.add('La has escuchado ${t.plays} ${t.plays == 1 ? 'vez' : 'veces'}');
      scored.add(Recommendation(track: t, kind: kind, score: s, reasons: reasons));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Variedad: primero un artista distinto por puesto; solo si faltan
    // canciones se repite artista (máximo 2). Así no se encierra en los mismos.
    final out = <Recommendation>[];
    final perArtist = <String, int>{};
    for (final limit in const [1, 2]) {
      for (final r in scored) {
        if (out.length >= n) break;
        if (out.contains(r)) continue;
        final a = (r.track.artist ?? '').toLowerCase();
        if ((perArtist[a] ?? 0) >= limit) continue;
        perArtist[a] = (perArtist[a] ?? 0) + 1;
        out.add(r);
      }
    }
    return out;
  }

  // ------------------------------------------- Inteligencia de sesiones

  /// Analiza tus sesiones (separadas por 30 min sin música) y descubre qué
  /// tienen en común las que más disfrutaste. Null si aún hay pocos datos.
  SessionInsight? sessionInsight() {
    final events = [...profile.history]..sort((a, b) => a.at.compareTo(b.at));
    final sessions = <List<ListenEvent>>[];
    for (final e in events) {
      if (sessions.isEmpty || e.at.difference(sessions.last.last.at) > const Duration(minutes: 30)) {
        sessions.add([e]);
      } else {
        sessions.last.add(e);
      }
    }
    final stats = <({double score, int minutes, double variety, double completion})>[];
    for (final s in sessions) {
      final plays = s.where((e) => e.type == ListenEventType.play).toList();
      if (plays.length < 3) continue;
      final completes = s.where((e) => e.type == ListenEventType.complete).length;
      final skips = s.where((e) => e.type == ListenEventType.skip).length;
      final likes = s.where((e) => e.type == ListenEventType.like).length;
      final artists = {for (final p in plays) profile.tracks[p.key]?.artist ?? p.key}.length;
      final completion = completes / plays.length;
      final minutes = max(1, s.last.at.difference(s.first.at).inMinutes);
      final score = completion + likes * .15 - skips / plays.length * .5;
      stats.add((score: score, minutes: minutes, variety: artists / plays.length * 10, completion: completion));
    }
    if (stats.length < 3) return null;
    stats.sort((a, b) => b.score.compareTo(a.score));
    final best = stats.take(max(1, (stats.length * .3).ceil())).toList();
    final minutes = (best.map((e) => e.minutes).reduce((a, b) => a + b) / best.length).round();
    final variety = best.map((e) => e.variety).reduce((a, b) => a + b) / best.length;
    final completion = (best.map((e) => e.completion).reduce((a, b) => a + b) / best.length * 100).round();
    final mix = variety >= 7
        ? 'mezclan muchos artistas'
        : variety >= 4
            ? 'combinan algunos artistas'
            : 'se quedan con pocos artistas';
    return SessionInsight(
      sessions: stats.length,
      bestMinutes: minutes,
      bestVariety: variety,
      bestCompletion: completion,
      summary: 'Tus mejores sesiones duran unos $minutes min, $mix y terminas el $completion % de las canciones.',
    );
  }

  /// Preferencia de variedad aprendida de tus mejores sesiones (0 = pocos artistas, 1 = muchos).
  double get varietyPreference => ((sessionInsight()?.bestVariety ?? 5) / 10).clamp(0.0, 1.0).toDouble();

  // ------------------------------------------------ Radar de descubrimiento

  /// Artistas nuevos parecidos a tus favoritos, y con quién se parecen.
  Future<List<({String artist, String because, int? fans, String? picture, String? topTrack})>> radar({
    int seeds = 3,
    int max = 8,
  }) async {
    final s = similar;
    if (s == null) return const [];
    final known = {for (final t in profile.tracks.values) (t.artist ?? '').toLowerCase()};
    final out = <({String artist, String because, int? fans, String? picture, String? topTrack})>[];
    final seen = <String>{};
    for (final (seed, _) in profile.topArtists(seeds)) {
      try {
        for (final a in await s.similarTo(seed, max: 6)) {
          final low = a.name.toLowerCase();
          if (known.contains(low) || seen.contains(low) || (settings?.isBlocked(null, a.name) ?? false)) continue;
          seen.add(low);
          out.add((
            artist: a.name,
            because: seed,
            fans: a.fans,
            picture: a.picture,
            topTrack: a.topTracks.isEmpty ? null : a.topTracks.first,
          ));
        }
      } catch (_) {}
      if (out.length >= max) break;
    }
    // Nivel de descubrimiento: «joyas ocultas» primero los menos conocidos.
    if ((settings?.discoveryLevel ?? 1) == 2) {
      out.sort((a, b) => (a.fans ?? 0).compareTo(b.fans ?? 0));
    } else if ((settings?.discoveryLevel ?? 1) == 0) {
      out.sort((a, b) => (b.fans ?? 0).compareTo(a.fans ?? 0));
    }
    return out.take(max).toList();
  }
}
