import '../../core/storage/json_store.dart';
import '../music_profile/music_profile.dart';

enum RepeatKind { song, artist }

/// Algo que está sonando demasiado.
class RepeatAlert {
  const RepeatAlert(this.kind, this.key, this.name, this.count, this.window,
      {this.share, this.intentional = false});
  final RepeatKind kind;

  /// trackKey (canción) o artista en minúsculas.
  final String key;
  final String name;
  final int count;
  final Duration window;

  /// Para artistas: parte de lo último que escuchaste (0–1).
  final double? share;

  /// La repites a propósito (la devolviste o le diste «me gusta»): se avisa más suave.
  final bool intentional;

  String get message => switch (kind) {
        RepeatKind.song => intentional
            ? '«$name» sonó $count veces ${_when(window)}. Se nota que te encanta; si quieres variar, tengo opciones.'
            : '«$name» sonó $count veces ${_when(window)}. ¿Probamos otra cosa?',
        RepeatKind.artist =>
          '$name es el ${((share ?? 0) * 100).round()} % de lo último que escuchaste ($count canciones). ¿Algo parecido de otro artista?',
      };

  static String _when(Duration w) => w <= const Duration(hours: 24) ? 'hoy' : 'esta semana';
}

/// Detector de repeticiones: avisa cuando una canción o un artista aparece
/// demasiado y sugiere alternativas. No regaña: un aviso por cosa y por día,
/// y «Está bien, me gusta» lo calla una semana.
class RepetitionDetector {
  RepetitionDetector({DateTime Function()? clock, this.store}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final JsonStore? store;

  Future<void> load() async {
    final d = await store?.load();
    snoozed.clear();
    for (final e in ((d?['snoozed'] as Map?) ?? const {}).entries) {
      final at = DateTime.tryParse('${e.value}');
      if (at != null) snoozed['${e.key}'] = at;
    }
  }

  /// Canción: 5 veces en 24 h o 12 en 7 días. Artista: más del 60 % de las
  /// últimas 25 canciones (con al menos 15).
  static const songDay = 5, songWeek = 12, artistWindow = 25, artistMin = 15;
  static const artistShare = 0.6;

  /// Silenciados por el usuario hasta una fecha.
  final Map<String, DateTime> snoozed = {};

  /// Último aviso de cada cosa (uno por día).
  final Map<String, DateTime> _shown = {};

  List<RepeatAlert> scan(MusicProfile profile) {
    final now = _clock();
    final plays = profile.history.where((e) => e.type == ListenEventType.play).toList();
    final out = <RepeatAlert>[];

    final day = <String, int>{}, week = <String, int>{};
    for (final e in plays) {
      final age = now.difference(e.at);
      if (age > const Duration(days: 7) || age.isNegative) continue;
      week[e.key] = (week[e.key] ?? 0) + 1;
      if (age <= const Duration(hours: 24)) day[e.key] = (day[e.key] ?? 0) + 1;
    }
    for (final key in week.keys) {
      final d = day[key] ?? 0, w = week[key]!;
      if (d < songDay && w < songWeek) continue;
      final daily = d >= songDay;
      final window = daily ? const Duration(hours: 24) : const Duration(days: 7);
      final count = daily ? d : w;
      final t = profile.tracks[key];
      final intentional = t != null && (t.repeats > 0 || t.likes > 0);
      out.add(RepeatAlert(RepeatKind.song, key, t?.title ?? key.split('|').first, count, window,
          intentional: intentional));
    }

    final recent = plays.where((e) => now.difference(e.at) <= const Duration(days: 2)).toList();
    final last = recent.length > artistWindow ? recent.sublist(recent.length - artistWindow) : recent;
    if (last.length >= artistMin) {
      final byArtist = <String, int>{};
      final names = <String, String>{};
      for (final e in last) {
        final a = profile.tracks[e.key]?.artist;
        if (a == null || a.trim().isEmpty) continue;
        final k = a.toLowerCase().trim();
        byArtist[k] = (byArtist[k] ?? 0) + 1;
        names[k] = a;
      }
      for (final e in byArtist.entries) {
        final share = e.value / last.length;
        if (share > artistShare) {
          out.add(RepeatAlert(RepeatKind.artist, e.key, names[e.key]!, e.value, const Duration(days: 2),
              share: share));
        }
      }
    }
    out.removeWhere((a) {
      final until = snoozed['${a.kind.name}:${a.key}'];
      return until != null && now.isBefore(until);
    });
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Avisos nuevos (no mostrados hoy). Los marca como mostrados.
  List<RepeatAlert> fresh(MusicProfile profile) {
    final now = _clock();
    final list = scan(profile).where((a) {
      final at = _shown['${a.kind.name}:${a.key}'];
      return at == null || now.difference(at) > const Duration(hours: 24);
    }).toList();
    for (final a in list) {
      _shown['${a.kind.name}:${a.key}'] = now;
    }
    return list;
  }

  /// «Está bien, me gusta»: no avisar de esto por 7 días.
  void snooze(RepeatAlert a, {Duration duration = const Duration(days: 7)}) {
    snoozed['${a.kind.name}:${a.key}'] = _clock().add(duration);
    store?.save({'snoozed': {for (final e in snoozed.entries) e.key: e.value.toIso8601String()}}).catchError((_) {});
  }

  void clear() {
    snoozed.clear();
    _shown.clear();
    store?.save({'snoozed': <String, String>{}}).catchError((_) {});
  }
}
