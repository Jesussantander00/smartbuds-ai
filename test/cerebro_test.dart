import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/brain/music_brain.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;
  late AppSettings settings;
  late MusicBrain brain;

  setUp(() {
    now = DateTime(2026, 6, 1, 9);
    profile = MusicProfile(clock: () => now);
    settings = AppSettings();
    brain = MusicBrain(profile: profile, settings: settings, clock: () => now);
  });

  void listen(String title, String artist, {int minutes = 4}) {
    profile.observe(PlayerStatus(
      playerId: 'yt',
      packageName: 'yt',
      appName: 'YouTube',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    ));
    now = now.add(Duration(minutes: minutes));
  }

  test('recomienda con su porqué, sin repetir lo reciente y con variedad', () {
    for (var i = 0; i < 6; i++) {
      listen('Feid $i', 'Feid');
    }
    for (var i = 0; i < 3; i++) {
      listen('Karol $i', 'Karol G');
    }
    for (var i = 0; i < 12; i++) {
      listen('Relleno $i', 'Otro $i');
    }
    profile.likeTrack(MusicProfile.keyFor('Feid 0', 'Feid'));
    final recs = brain.recommend(BrainContext(now: now), n: 5);
    expect(recs, isNotEmpty);
    expect(recs.every((r) => r.reasons.isNotEmpty), isTrue);
    final perArtist = <String, int>{};
    for (final r in recs) {
      perArtist[r.track.artist!] = (perArtist[r.track.artist!] ?? 0) + 1;
    }
    expect(perArtist.values.every((n) => n <= 2), isTrue);
    final recent = profile.recentKeys(10);
    expect(recs.any((r) => recent.contains(r.track.key)), isFalse);
  });

  test('aprende: acierto sube la confianza, fallo la baja', () {
    expect(brain.weightOf(RecKind.favorite), 1.0);
    brain.learn(RecKind.favorite, liked: true);
    expect(brain.weightOf(RecKind.favorite), greaterThan(1.0));
    for (var i = 0; i < 30; i++) {
      brain.learn(RecKind.rediscover, liked: false);
    }
    expect(brain.weightOf(RecKind.rediscover), 0.5); // nunca baja de 0,5
  });

  test('la mezcla del ambiente pesa cuando se pide', () {
    profile.setMood('para entrenar');
    for (var i = 0; i < 4; i++) {
      listen('Gym $i', 'A$i');
    }
    for (var i = 0; i < 12; i++) {
      listen('Otra $i', 'B$i');
    }
    final recs = brain.recommend(BrainContext(now: now.add(const Duration(hours: 3)), mood: 'para entrenar'));
    expect(recs.first.kind, RecKind.mood);
  });

  test('inteligencia de sesiones', () {
    for (var s = 0; s < 4; s++) {
      for (var i = 0; i < 5; i++) {
        listen('S$s-$i', 'Artista $i');
      }
      now = now.add(const Duration(hours: 3));
    }
    final insight = brain.sessionInsight();
    expect(insight, isNotNull);
    expect(insight!.summary, contains('Tus mejores sesiones'));
  });

  test('reconocimiento de ambiente en frases libres', () {
    const p = CommandParser();
    expect((p.parseIntent('estoy nostálgico') as MoodIntent).mood, 'nostálgica');
    expect((p.parseIntent('me siento con energía') as MoodIntent).mood, 'con energía');
    expect((p.parseIntent('ando relajado') as MoodIntent).mood, 'tranquila');
    expect(CommandParser.detectMood('quiero algo de despecho')?.$1, 'de despecho');
  });
}
