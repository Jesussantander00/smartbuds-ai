import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/connectors/weather/weather.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

PlayerStatus song(String title, {String artist = 'Artista'}) => PlayerStatus(
      playerId: 'yt',
      packageName: 'com.google.android.apps.youtube.music',
      appName: 'YouTube Music',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    );

void main() {
  const p = CommandParser();

  group('Nuevas órdenes de voz', () {
    test('volumen exacto', () {
      expect((p.parseIntent('volumen al cincuenta') as VolumeIntent).percent, 50);
      expect((p.parseIntent('pon el volumen en 30') as VolumeIntent).percent, 30);
      expect((p.parseIntent('volumen al máximo') as VolumeIntent).percent, 100);
      expect((p.parseIntent('volumen a la mitad') as VolumeIntent).percent, 50);
      expect(p.parseVolume('volumen al 150'), isNull);
    });

    test('cola: «después pon …»', () {
      expect((p.parseIntent('después pon Ojalá de Ryan Castro') as QueueIntent).query,
          'ojala de ryan castro');
      expect((p.parseIntent('después pon') as QueueIntent).query, isNull);
    });

    test('por la letra', () {
      expect((p.parseIntent('la que dice baby no me llames') as LyricsIntent).words,
          'baby no me llames');
      expect((p.parseIntent('la que dice') as LyricsIntent).words, isNull);
    });

    test('nunca más', () {
      expect((p.parseIntent('nunca más esta') as BlockIntent).artist, isFalse);
      expect((p.parseIntent('nunca más este artista') as BlockIntent).artist, isTrue);
    });

    test('varias órdenes en una frase', () {
      final m = p.parseIntent('cambia y sube') as MultiIntent;
      expect(m.parts.length, 2);
      expect((m.parts[0] as CommandIntent).command, MusicCommand.next);
      expect((m.parts[1] as CommandIntent).command, MusicCommand.volumeUp);
      expect(p.parseIntent('busca vivir mi vida y bailar'), isA<SearchIntent>());
    });

    test('olvidadas y semana', () {
      expect(p.parseIntent('pon favoritas olvidadas'), isA<ForgottenIntent>());
      expect(p.parseIntent('comparte mi semana'), isA<ShareWeekIntent>());
    });

    test('respuestas cortas: primera frase', () {
      expect(VoiceEngine.shorten('Listo. Apago la música en 20 minutos.'), 'Listo.');
      expect(VoiceEngine.shorten('Sin punto'), 'Sin punto');
    });

    test('historial legible', () {
      expect(VoiceEngine.describe(const VolumeIntent(40)), 'Volumen al 40 %');
      expect(VoiceEngine.describe(const MultiIntent([
        CommandIntent(MusicCommand.next),
        CommandIntent(MusicCommand.volumeUp),
      ])), 'Siguiente canción + Subir volumen');
    });
  });

  group('Perfil: nuevas funciones', () {
    late DateTime now;
    late MusicProfile profile;

    setUp(() {
      now = DateTime(2026, 1, 1, 10);
      profile = MusicProfile(clock: () => now);
    });

    void listen(String title, {String artist = 'Artista', int seconds = 120}) {
      profile.observe(song(title, artist: artist));
      now = now.add(Duration(seconds: seconds));
    }

    test('favoritas olvidadas', () {
      listen('Vieja');
      listen('Otra');
      profile.likeTrack(MusicProfile.keyFor('Vieja', 'Artista'));
      expect(profile.forgottenFavorites(), isEmpty);
      now = now.add(const Duration(days: 30));
      expect(profile.forgottenFavorites().map((t) => t.title), contains('Vieja'));
    });

    test('bloqueadas no se eligen', () {
      profile.likeTrack('x'); // no existe: no hace nada
      listen('A');
      listen('B');
      profile.likeTrack(MusicProfile.keyFor('A', 'Artista'));
      profile.isBlocked = (t, a) => t == 'A';
      now = now.add(const Duration(days: 30));
      expect(profile.forgottenFavorites(), isEmpty);
    });

    test('lista automática por ambiente', () {
      profile.setMood('para entrenar');
      for (final t in ['A', 'B', 'C', 'D']) {
        listen(t);
      }
      listen('E');
      expect(profile.moodTracks['para entrenar']!.length, greaterThanOrEqualTo(3));
      // Recién sonaron: no se repiten enseguida.
      expect(profile.pickMood('para entrenar'), isNull);
      now = now.add(const Duration(hours: 3)); // fuera del ambiente
      for (var i = 0; i < 10; i++) {
        listen('Otra $i');
      }
      expect(profile.pickMood('para entrenar'), isNotNull);
      expect(profile.pickMood('para dormir'), isNull);
    });

    test('exportar e importar', () {
      listen('A');
      listen('B');
      profile.likeTrack(MusicProfile.keyFor('A', 'Artista'));
      final copy = profile.exportJson();
      final other = MusicProfile(clock: () => now);
      expect(other.importJson(copy), greaterThan(0));
      expect(other.tracks.containsKey(MusicProfile.keyFor('A', 'Artista')), isTrue);
      expect(other.importJson('hola'), -1);
    });

    test('comparar gustos', () {
      listen('A', artist: 'Karol G');
      listen('B', artist: 'Feid');
      listen('C', artist: 'Feid');
      final code = profile.tasteCode();
      final r = profile.compareTaste('mira: $code');
      expect(r, isNotNull);
      expect(r!.shared, containsAll(['Karol G', 'Feid']));
      expect(r.percent, greaterThan(50));
      expect(profile.compareTaste('nada'), isNull);
    });
  });

  group('Ajustes', () {
    test('bloquear canción y artista', () {
      final s = AppSettings();
      s.block(title: 'Tusa', artist: 'Karol G');
      expect(s.isBlocked('tusa', 'karol g'), isTrue);
      expect(s.isBlocked('Bichota', 'Karol G'), isFalse);
      s.block(artist: 'Karol G', wholeArtist: true);
      expect(s.isBlocked('Bichota', 'Karol G'), isTrue);
      s.unblock('karol g', artist: true);
      expect(s.isBlocked('Bichota', 'Karol G'), isFalse);
    });
  });

  test('clima → ambiente', () {
    expect(WeatherService.moodFor(61, 18, 'Medellín').mood, 'tranquila');
    expect(WeatherService.moodFor(0, 30, 'Cali').mood, 'alegre');
    expect(WeatherService.moodFor(3, 10, '').description, contains('frío'));
  });
}
