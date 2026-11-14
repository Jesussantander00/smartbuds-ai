import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/storage/json_store.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/activity/activity.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

/// PR #39: recomendaciones según la actividad.
void main() {
  late DateTime now;
  late ActivityTracker t;
  late MusicProfile profile;

  TrackStats track(String title, String artist, {String? mood, int completes = 0, int skips = 0}) {
    final key = MusicProfile.keyFor(title, artist);
    final s = TrackStats(key: key, title: title, artist: artist)
      ..completes = completes
      ..skips = skips;
    profile.tracks[key] = s;
    if (mood != null) (profile.moodTracks[mood] ??= <String>{}).add(key);
    return s;
  }

  setUp(() {
    now = DateTime(2026, 11, 16, 15); // lunes 3 p. m.
    t = ActivityTracker(clock: () => now, store: MemoryJsonStore());
    profile = MusicProfile();
  });

  test('voz: «estoy estudiando», «voy a entrenar», «terminé»', () {
    const p = CommandParser();
    expect((p.parseIntent('Estoy estudiando') as ActivityIntent).activity, 'estudiar');
    expect((p.parseIntent('voy al gimnasio') as ActivityIntent).activity, 'ejercicio');
    expect((p.parseIntent('quiero descansar') as ActivityIntent).activity, 'descansar');
    expect((p.parseIntent('ya terminé') as ActivityIntent).activity, isNull);
    // No rompe lo que ya existía.
    expect(p.parseIntent('pon algo para entrenar'), isA<MoodIntent>());
    expect(p.parseIntent('modo estudio'), isA<UsageProfileIntent>());
  });

  test('para estudiar: lo tranquilo y conocido; nunca lo de fiesta', () {
    track('Calma', 'Pedro Capó', mood: 'tranquila', completes: 5);
    track('Perreo', 'Feid', mood: 'de fiesta', completes: 9);
    final picks = t.recommend(Activity.estudiar, profile);
    expect(picks.map((p) => p.track.title), ['Calma']);
  });

  test('para ejercicio: lo que tiene energía', () {
    track('Calma', 'Pedro Capó', mood: 'tranquila', completes: 5);
    track('Power', 'Kanye', mood: 'para entrenar', completes: 1);
    expect(t.recommend(Activity.ejercicio, profile).first.track.title, 'Power');
  });

  test('aprende: lo que terminaste estudiando sube; lo que saltaste estudiando sale', () {
    track('A', 'x', mood: 'para concentrarte');
    track('B', 'y', mood: 'para concentrarte');
    t.start(Activity.estudiar);
    final ka = MusicProfile.keyFor('A', 'x'), kb = MusicProfile.keyFor('B', 'y');
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(minutes: 4));
      profile.history.add(ListenEvent(now, ka, ListenEventType.complete));
      profile.history.add(ListenEvent(now, kb, ListenEventType.skip));
    }
    now = now.add(const Duration(minutes: 1));
    final picks = t.recommend(Activity.estudiar, profile);
    expect(picks.map((p) => p.track.title), ['A']);
    expect(picks.first.reasons.first, contains('La terminaste 3 veces'));
    // Lo que pasa haciendo otra cosa no cuenta para estudiar.
    expect(t.statsFor(Activity.ejercicio, profile.history), isEmpty);
  });

  test('una actividad se cierra sola a las 3 horas y cambiar de actividad cierra la anterior', () {
    t.start(Activity.trabajar);
    now = now.add(const Duration(hours: 1));
    t.start(Activity.descansar);
    expect(t.sessions.first.end, isNotNull);
    expect(t.activity, Activity.descansar);
    now = now.add(const Duration(hours: 4));
    expect(t.current, isNull);
  });

  test('rutina: si sueles estudiar a esta hora (3 veces), lo sugiere', () {
    for (final weeks in [1, 2, 3]) {
      final day = DateTime(2026, 11, 16).subtract(Duration(days: 7 * weeks)); // lunes anteriores
      t.sessions.add(ActivitySession(Activity.estudiar, day.add(const Duration(hours: 15, minutes: 10)),
          day.add(const Duration(hours: 16))));
    }
    expect(t.routineSuggestion(), Activity.estudiar);
    now = DateTime(2026, 11, 16, 20);
    expect(t.routineSuggestion(), isNull, reason: 'otra hora');
  });

  test('se guarda y se carga; en modo privado no se guarda', () async {
    final store = MemoryJsonStore();
    final a = ActivityTracker(clock: () => now, store: store)..start(Activity.ejercicio);
    await Future<void>.delayed(Duration.zero);
    final b = ActivityTracker(clock: () => now, store: store);
    await b.load();
    expect(b.activity, Activity.ejercicio);
    a.isPrivate = () => true;
    a.start(Activity.estudiar);
    await Future<void>.delayed(Duration.zero);
    await b.load();
    expect(b.activity, Activity.ejercicio);
  });
}
