import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/brain/music_brain.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';
import 'package:smartbuds_ai/features/stats/evolution.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;

  setUp(() {
    now = DateTime(2026, 1, 10, 18);
    profile = MusicProfile(clock: () => now);
  });

  void listen(String title, String artist, {int minutes = 4}) {
    profile.observe(PlayerStatus(
      playerId: 'sp',
      packageName: 'sp',
      appName: 'Spotify',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    ));
    now = now.add(Duration(minutes: minutes));
  }

  void month(int m, String artist, {int songs = 12, String? extra}) {
    now = DateTime(2026, m, 10, 18);
    for (var i = 0; i < songs; i++) {
      listen('$artist $i', artist);
    }
    if (extra != null) {
      for (var i = 0; i < 4; i++) {
        listen('$extra $i', extra);
      }
    }
  }

  test('meses, etapas, quién sube y quién baja', () {
    month(1, 'Don Omar');
    month(2, 'Don Omar');
    month(3, 'Don Omar', extra: 'Feid');
    month(4, 'Feid');
    month(5, 'Feid');
    month(6, 'Feid', extra: 'Young Miko');
    final e = TasteEvolution.from(profile, now: DateTime(2026, 6, 30));
    expect(e.months, hasLength(6));
    expect(e.months.first.topArtist, 'Don Omar');
    expect(e.months.last.topArtist, 'Feid');
    expect(e.stages.map((s) => s.artist), ['Don Omar', 'Feid']);
    expect(e.stages.first.months, 3);
    expect(e.rising, contains('Feid'));
    expect(e.fading, contains('Don Omar'));
    expect(e.months[2].newArtists, contains('Feid'));
    expect(e.discovered, 2); // Feid y Young Miko (Don Omar es el inicio de la memoria)
    expect(e.keeper, 'Feid');
    final s = e.summary();
    expect(s, contains('Ahora escuchas más a Feid'));
    expect(s, contains('Antes escuchabas más a Don Omar'));
  });

  test('sin historial lo dice', () {
    expect(TasteEvolution.from(profile).summary(), contains('Todavía no tengo'));
  });

  test('voz: «¿cómo han cambiado mis gustos este año?»', () {
    const p = CommandParser();
    expect(p.parseIntent('¿Cómo han cambiado mis gustos este año?'), isA<TasteEvolutionIntent>());
    expect(p.parseIntent('mi evolución musical'), isA<TasteEvolutionIntent>());
  });

  group('ambiente de la sesión', () {
    test('lo que pediste hace poco manda', () {
      profile.setMood('entrenar');
      final brain = MusicBrain(profile: profile, settings: AppSettings(), clock: () => now);
      expect(brain.ambience()?.mood, 'entrenar');
      now = now.add(const Duration(hours: 3));
      expect(brain.ambience(), isNull, reason: 'pasaron más de 2 horas y no hay listas');
    });

    test('si no, lo que se nota en las últimas canciones', () {
      for (var i = 0; i < 5; i++) {
        listen('Calma $i', 'Artista');
      }
      profile.moodTracks['tranquila'] = {
        MusicProfile.keyFor('Calma 3', 'Artista'),
        MusicProfile.keyFor('Calma 4', 'Artista'),
      };
      final brain = MusicBrain(profile: profile, settings: AppSettings(), clock: () => now);
      final a = brain.ambience();
      expect(a?.mood, 'tranquila');
      expect(a?.reason, contains('2 de las últimas 5'));
    });
  });
}
