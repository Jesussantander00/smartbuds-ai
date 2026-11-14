import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/storage/json_store.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/discovery/repetition.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

/// PR #41: detector de repeticiones.
void main() {
  late DateTime now;
  late MusicProfile profile;
  late RepetitionDetector d;

  String track(String title, String artist, {int likes = 0, int repeats = 0}) {
    final key = MusicProfile.keyFor(title, artist);
    profile.tracks[key] = TrackStats(key: key, title: title, artist: artist)
      ..likes = likes
      ..repeats = repeats;
    return key;
  }

  void play(String key, {Duration ago = Duration.zero}) =>
      profile.history.add(ListenEvent(now.subtract(ago), key, ListenEventType.play));

  setUp(() {
    now = DateTime(2026, 11, 14, 20);
    profile = MusicProfile();
    d = RepetitionDetector(clock: () => now, store: MemoryJsonStore());
  });

  test('una canción 5 veces hoy: aviso', () {
    final k = track('Tusa', 'Karol G');
    for (var i = 0; i < 5; i++) {
      play(k, ago: Duration(hours: i));
    }
    final a = d.scan(profile).single;
    expect(a.kind, RepeatKind.song);
    expect(a.message, '«Tusa» sonó 5 veces hoy. ¿Probamos otra cosa?');
  });

  test('4 veces hoy no es repetir demasiado', () {
    final k = track('Tusa', 'Karol G');
    for (var i = 0; i < 4; i++) {
      play(k, ago: Duration(hours: i));
    }
    expect(d.scan(profile), isEmpty);
  });

  test('12 veces en la semana: aviso semanal', () {
    final k = track('Tusa', 'Karol G');
    for (var i = 0; i < 12; i++) {
      play(k, ago: Duration(hours: 13 * i + 1));
    }
    expect(d.scan(profile).single.message, contains('esta semana'));
  });

  test('si la repites a propósito (me gusta), el aviso es amable', () {
    final k = track('Tusa', 'Karol G', likes: 1);
    for (var i = 0; i < 5; i++) {
      play(k, ago: Duration(minutes: 20 * i));
    }
    expect(d.scan(profile).single.message, contains('te encanta'));
  });

  test('un artista con más del 60 % de lo último', () {
    final feid = [for (var i = 0; i < 12; i++) track('F$i', 'Feid')];
    final otros = [for (var i = 0; i < 6; i++) track('O$i', 'Otro $i')];
    var m = 0;
    for (final k in [...feid, ...otros]) {
      play(k, ago: Duration(minutes: 200 - 10 * m++));
    }
    final a = d.scan(profile).single;
    expect(a.kind, RepeatKind.artist);
    expect(a.message, startsWith('Feid es el 67 %'));
  });

  test('«Está bien, me gusta» lo calla una semana (y se guarda)', () async {
    final k = track('Tusa', 'Karol G');
    for (var i = 0; i < 5; i++) {
      play(k, ago: Duration(hours: i));
    }
    final store = MemoryJsonStore();
    final det = RepetitionDetector(clock: () => now, store: store);
    det.snooze(det.scan(profile).single);
    expect(det.scan(profile), isEmpty);
    final again = RepetitionDetector(clock: () => now, store: store);
    await again.load();
    expect(again.scan(profile), isEmpty);
    now = now.add(const Duration(days: 8));
    for (var i = 0; i < 5; i++) {
      play(k, ago: Duration(hours: i));
    }
    expect(again.scan(profile), isNotEmpty);
  });

  test('un aviso por cosa y por día', () {
    final k = track('Tusa', 'Karol G');
    for (var i = 0; i < 5; i++) {
      play(k, ago: Duration(hours: i));
    }
    expect(d.fresh(profile), hasLength(1));
    expect(d.fresh(profile), isEmpty);
  });

  test('voz', () {
    const p = CommandParser();
    expect((p.parseIntent('¿Estoy repitiendo mucho?') as RepetitionIntent).vary, isFalse);
    expect((p.parseIntent('varía un poco') as RepetitionIntent).vary, isTrue);
    expect((p.parseIntent('cambia de artista') as RepetitionIntent).vary, isTrue);
  });
}
