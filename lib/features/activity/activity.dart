import '../../core/storage/json_store.dart';
import '../assistant/smart_queue.dart';
import '../music_profile/music_profile.dart';

/// Lo que estás haciendo mientras escuchas.
enum Activity { estudiar, trabajar, descansar, ejercicio }

/// Reglas de cada actividad: qué energía conviene y si es momento de sorpresas.
class ActivityRules {
  const ActivityRules(this.label, this.mood, this.query, this.minEnergy, this.maxEnergy,
      {required this.familiar, required this.blurb});
  final String label;

  /// Ambiente de SmartBuds con el que aprende (las listas por ambiente).
  final String mood;

  /// Búsqueda si todavía no hay datos tuyos.
  final String query;
  final int minEnergy, maxEnergy;

  /// Preferir canciones conocidas (sin sorpresas que distraigan).
  final bool familiar;
  final String blurb;
}

class ActivityEngine {
  static const rules = <Activity, ActivityRules>{
    Activity.estudiar: ActivityRules('Estudiar', 'para concentrarte', 'musica para estudiar concentracion', 0, 2,
        familiar: true, blurb: 'tranquila y conocida, sin sorpresas que distraigan'),
    Activity.trabajar: ActivityRules('Trabajar', 'para concentrarte', 'musica para trabajar', 1, 3,
        familiar: true, blurb: 'constante y conocida, con algo de ritmo'),
    Activity.descansar: ActivityRules('Descansar', 'tranquila', 'musica tranquila relajante', 0, 1,
        familiar: false, blurb: 'suave, para bajar el ritmo'),
    Activity.ejercicio: ActivityRules('Ejercicio', 'para entrenar', 'musica para entrenar', 4, 5,
        familiar: false, blurb: 'con energía, sin bajones'),
  };

  static Activity? byName(String? name) =>
      Activity.values.where((a) => a.name == name).firstOrNull;

  /// Actividad a partir de un ambiente («pon algo para estudiar» → estudiar).
  static Activity? fromMood(String? mood) => switch (mood) {
        'para concentrarte' => Activity.estudiar,
        'para entrenar' => Activity.ejercicio,
        'para dormir' => Activity.descansar,
        _ => null,
      };
}

/// Un rato haciendo algo (para aprender qué música te sirve en cada actividad).
class ActivitySession {
  ActivitySession(this.activity, this.start, [this.end]);
  final Activity activity;
  final DateTime start;
  DateTime? end;

  bool contains(DateTime t, DateTime now) => !t.isBefore(start) && t.isBefore(end ?? now);

  Map<String, dynamic> toJson() =>
      {'a': activity.name, 's': start.toIso8601String(), if (end != null) 'e': end!.toIso8601String()};

  static ActivitySession? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = ActivityEngine.byName(j['a'] as String?);
    final s = DateTime.tryParse('${j['s']}');
    if (a == null || s == null) return null;
    return ActivitySession(a, s, DateTime.tryParse('${j['e'] ?? ''}'));
  }
}

/// Una recomendación para la actividad, con sus razones.
class ActivityPick {
  const ActivityPick(this.track, this.score, this.reasons);
  final TrackStats track;
  final double score;
  final List<String> reasons;
  String get query => [track.title, if (track.artist != null) track.artist].join(' ');
}

/// Recuerda tus actividades y recomienda según lo que haces. Todo en el
/// teléfono. No adivina la actividad con sensores: la dices tú (o tu modo de
/// uso / ambiente) y, como mucho, la sugiere por tu rutina.
class ActivityTracker {
  ActivityTracker({DateTime Function()? clock, this.store}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final JsonStore? store;

  /// Modo privado: no se guardan las actividades.
  bool Function()? isPrivate;

  /// Una actividad se cierra sola después de este tiempo.
  static const maxLength = Duration(hours: 3);
  static const maxSessions = 300;

  final List<ActivitySession> sessions = [];

  ActivitySession? get current {
    final s = sessions.isEmpty ? null : sessions.last;
    if (s == null || s.end != null) return null;
    if (_clock().difference(s.start) > maxLength) {
      s.end = s.start.add(maxLength);
      _save();
      return null;
    }
    return s;
  }

  Activity? get activity => current?.activity;

  Future<void> load() async {
    final d = await store?.load();
    sessions
      ..clear()
      ..addAll(((d?['sessions'] as List?) ?? const []).map(ActivitySession.fromJson).whereType<ActivitySession>());
  }

  void _save() {
    final s = store;
    if (s == null || (isPrivate?.call() ?? false)) return;
    s.save({'sessions': [for (final x in sessions) x.toJson()]}).catchError((_) {});
  }

  void start(Activity a) {
    final c = current;
    if (c?.activity == a) return;
    final now = _clock();
    c?.end = now;
    sessions.add(ActivitySession(a, now));
    if (sessions.length > maxSessions) sessions.removeAt(0);
    _save();
  }

  void stop() {
    final c = current;
    if (c == null) return;
    c.end = _clock();
    _save();
  }

  void clear() {
    sessions.clear();
    _save();
  }

  /// Qué pasó con cada canción mientras hacías [a]: terminadas y saltadas.
  Map<String, ({int done, int skipped})> statsFor(Activity a, List<ListenEvent> history) {
    final now = _clock();
    final mine = sessions.where((s) => s.activity == a).toList();
    final out = <String, ({int done, int skipped})>{};
    if (mine.isEmpty) return out;
    for (final e in history) {
      if (!mine.any((s) => s.contains(e.at, now))) continue;
      final cur = out[e.key] ?? (done: 0, skipped: 0);
      switch (e.type) {
        case ListenEventType.complete || ListenEventType.repeat || ListenEventType.like:
          out[e.key] = (done: cur.done + 1, skipped: cur.skipped);
        case ListenEventType.skip || ListenEventType.dislike:
          out[e.key] = (done: cur.done, skipped: cur.skipped + 1);
        case ListenEventType.play:
          break;
      }
    }
    return out;
  }

  /// Canciones para [a]: lo que terminaste haciendo eso, la energía que
  /// conviene y (para estudiar/trabajar) que sean conocidas.
  List<ActivityPick> recommend(Activity a, MusicProfile profile, {int n = 5, Set<String> avoid = const {}}) {
    final rule = ActivityEngine.rules[a]!;
    final stats = statsFor(a, profile.history);
    final moodOf = <String, String>{};
    for (final e in profile.moodTracks.entries) {
      for (final k in e.value) {
        moodOf[k] ??= e.key;
      }
    }
    final now = _clock();
    final picks = <ActivityPick>[];
    for (final t in profile.tracks.values) {
      if (t.dislikes > t.likes || avoid.contains(t.key)) continue;
      final reasons = <String>[];
      var score = 0.0;
      final s = stats[t.key];
      if (s != null) {
        score += s.done * 2 - s.skipped * 3;
        if (s.done > 0) {
          reasons.add('La terminaste ${s.done} ${s.done == 1 ? 'vez' : 'veces'} mientras hacías esto');
        }
        if (s.skipped >= 2 && s.done == 0) continue; // no te sirve para esto
      }
      final inMood = profile.moodTracks[rule.mood]?.contains(t.key) ?? false;
      if (inMood) {
        score += 2;
        reasons.add('Está en tu mezcla ${rule.mood}');
      }
      final energy = SmartQueue.moodEnergy[moodOf[t.key]] ?? SmartQueue.energyFromWords('${t.title} ${t.artist ?? ''}');
      if (energy != null) {
        if (energy >= rule.minEnergy && energy <= rule.maxEnergy) {
          score += 1.5;
        } else {
          score -= 2 * ((energy < rule.minEnergy ? rule.minEnergy - energy : energy - rule.maxEnergy));
        }
      }
      if (rule.familiar) {
        final known = t.completes + t.repeats;
        if (known >= 3) {
          score += 1;
          if (reasons.isEmpty) reasons.add('La conoces bien: no distrae');
        }
        if (t.skips > t.completes) score -= 1.5;
      } else if (t.likes > 0) {
        score += 0.5;
      }
      final last = t.lastPlayedAt;
      if (last != null && now.difference(last) < const Duration(hours: 2)) score -= 1.5; // sonó hace poco
      if (score <= 0 || (reasons.isEmpty && energy == null)) continue;
      if (reasons.isEmpty) reasons.add('Tiene la energía que va con ${rule.label.toLowerCase()}');
      picks.add(ActivityPick(t, score, reasons));
    }
    picks.sort((x, y) => y.score.compareTo(x.score));
    return picks.take(n).toList();
  }

  /// Si sueles empezar una actividad a esta hora (≥ 3 veces en las últimas
  /// 4 semanas, ±1 h, mismo tipo de día), la sugiere.
  Activity? routineSuggestion() {
    final now = _clock();
    if (current != null) return null;
    final weekend = now.weekday >= DateTime.saturday;
    final counts = <Activity, int>{};
    for (final s in sessions) {
      if (now.difference(s.start) > const Duration(days: 28)) continue;
      if ((s.start.weekday >= DateTime.saturday) != weekend) continue;
      final mins = (s.start.hour * 60 + s.start.minute) - (now.hour * 60 + now.minute);
      if (mins.abs() > 60) continue;
      counts[s.activity] = (counts[s.activity] ?? 0) + 1;
    }
    final best = counts.entries.where((e) => e.value >= 3).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return best.isEmpty ? null : best.first.key;
  }
}
