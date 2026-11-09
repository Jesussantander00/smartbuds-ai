import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

PlayerStatus song(String title, String artist) => PlayerStatus(
      playerId: 'yt',
      packageName: 'com.google.android.apps.youtube.music',
      appName: 'YouTube Music',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    );

void main() {
  late DateTime now;
  late MusicProfile profile;

  setUp(() {
    now = DateTime(2026, 6, 15, 10);
    profile = MusicProfile(clock: () => now);
  });

  void listen(String title, String artist, {int seconds = 200}) {
    profile.observe(song(title, artist));
    now = now.add(Duration(seconds: seconds));
  }

  test('detecta un cambio de gusto', () {
    // Hace dos meses: solo Feid.
    now = DateTime(2026, 4, 20, 10);
    for (var i = 0; i < 20; i++) {
      listen('F$i', 'Feid');
    }
    // Estas dos semanas: mucho Bad Bunny.
    now = DateTime(2026, 6, 10, 10);
    for (var i = 0; i < 12; i++) {
      listen('B$i', 'Bad Bunny');
    }
    final shift = profile.tasteShift();
    expect(shift.rising, contains('Bad Bunny'));
    expect(shift.fading, contains('Feid'));
  });

  test('sobreexpuestas: misma canción muchas veces en la semana', () {
    for (var i = 0; i < 9; i++) {
      listen('Tusa', 'Karol G');
      listen('Otra $i', 'X');
    }
    final tired = profile.overexposed();
    expect(tired.first.$1.title, 'Tusa');
    expect(tired.first.$2, greaterThanOrEqualTo(8));
  });

  test('evolución mes a mes', () {
    now = DateTime(2026, 5, 3, 10);
    for (var i = 0; i < 3; i++) {
      listen('A$i', 'Shakira');
    }
    now = DateTime(2026, 6, 3, 10);
    for (var i = 0; i < 3; i++) {
      listen('B$i', 'Juanes');
    }
    final evo = profile.evolution(months: 2);
    expect(evo.length, 2);
    expect(evo[0].artist, 'Shakira');
    expect(evo[1].artist, 'Juanes');
  });

  test('por qué te gusta', () {
    listen('Ojalá', 'Ryan Castro');
    listen('Ojalá', 'Ryan Castro');
    listen('Otra', 'X');
    profile.likeTrack(MusicProfile.keyFor('Ojalá', 'Ryan Castro'));
    final why = profile.whyYouLike(MusicProfile.keyFor('Ojalá', 'Ryan Castro'));
    expect(why.join(' '), contains('me gusta'));
    expect(profile.whyYouLike('nada|nadie').first, contains('nueva'));
  });

  test('voz: parecido y por qué', () {
    const p = CommandParser();
    expect(p.parseIntent('pon algo parecido'), isA<SimilarIntent>());
    expect(p.parseIntent('por qué me gusta esta'), isA<WhyIntent>());
  });
}
