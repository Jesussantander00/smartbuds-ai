import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/storage/json_store.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/speaker_guard.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

PlayerStatus playing(String title, {String artist = 'Artista'}) => PlayerStatus(
      playerId: 'yt',
      packageName: 'com.google.android.apps.youtube.music',
      appName: 'YouTube Music',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    );

void main() {
  group('MusicProfile', () {
    late DateTime now;
    late MusicProfile profile;

    setUp(() {
      now = t0;
      profile = MusicProfile(clock: () => now);
    });

    String key(String t) => MusicProfile.keyFor(t, 'Artista');

    test('escuchar ≥ 90 s cuenta como completa (+2)', () {
      profile.observe(playing('A'));
      now = now.add(const Duration(seconds: 120));
      profile.observe(playing('B'));
      expect(profile.tracks[key('A')]!.completes, 1);
      expect(profile.tracks[key('A')]!.score(profile.weights), 2);
    });

    test('«Cambia» en los primeros 30 s cuenta como salto (−2)', () {
      profile.observe(playing('A'));
      now = now.add(const Duration(seconds: 10));
      profile.noteCommand(MusicCommand.next);
      profile.observe(playing('B'));
      expect(profile.tracks[key('A')]!.skips, 1);
    });

    test('cambio automático rápido (sin «Cambia») no castiga la canción', () {
      profile.observe(playing('A'));
      now = now.add(const Duration(seconds: 10));
      profile.observe(playing('B'));
      expect(profile.tracks[key('A')]!.skips, 0);
    });

    test('«Devuelve» a una canción ya escuchada cuenta como repetición (+3)', () {
      profile.observe(playing('A'));
      now = now.add(const Duration(seconds: 100));
      profile.observe(playing('B'));
      now = now.add(const Duration(seconds: 5));
      profile.noteCommand(MusicCommand.previous);
      profile.observe(playing('A'));
      expect(profile.tracks[key('A')]!.repeats, 1);
    });

    test('me gusta / no me gusta sobre la canción actual', () {
      expect(profile.like(), isNull, reason: 'sin música no hay nada que marcar');
      profile.observe(playing('A'));
      profile.like();
      expect(profile.tracks[key('A')]!.likes, 1);
      profile.dislike();
      expect(profile.tracks[key('A')]!.score(profile.weights), 0);
    });

    test('pausado o sin título no cuenta', () {
      profile.observe(PlayerStatus(
          playerId: 'x', packageName: 'p', appName: 'X', state: PlaybackState.paused,
          title: 'A'));
      profile.observe(null);
      expect(profile.tracks, isEmpty);
    });

    test('pon algo que me guste: elige favoritas que no sonaron hace poco', () {
      for (final t in ['A', 'B', 'C']) {
        profile.observe(playing(t));
        profile.like();
        now = now.add(const Duration(seconds: 100));
      }
      for (var i = 0; i < 10; i++) {
        profile.observe(playing('X$i'));
        now = now.add(const Duration(seconds: 100));
      }
      final pick = profile.pickFavorite(random: Random(1));
      expect(pick, isNotNull);
      expect(['A', 'B', 'C'], contains(pick!.title));
    });

    test('sin datos, no inventa favoritas', () {
      expect(profile.pickFavorite(), isNull);
    });

    test('se guarda y se vuelve a cargar', () async {
      final store = MemoryJsonStore();
      final p1 = MusicProfile(store: store, clock: () => now);
      p1.observe(playing('A'));
      p1.like();
      p1.dispose(); // guarda
      final p2 = MusicProfile(store: store);
      await p2.load();
      expect(p2.tracks[key('A')]!.likes, 1);
      expect(p2.history, isNotEmpty);
    });

    test('artistas top suman sus canciones', () {
      profile.observe(playing('A', artist: 'Ryan Castro'));
      profile.like();
      expect(profile.topArtists().first.$1, 'Ryan Castro');
    });
  });

  group('Momentos del día', () {
    test('las favoritas de la mañana suben en la mañana', () {
      var now = DateTime(2026, 11, 7, 8); // mañana
      final profile = MusicProfile(clock: () => now);
      profile.observe(playing('Mañanera'));
      profile.like();
      now = DateTime(2026, 11, 7, 21); // noche
      profile.observe(playing('Nocturna'));
      profile.like();
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 100));
        profile.observe(playing('Relleno$i'));
      }
      expect(profile.tracks[MusicProfile.keyFor('Mañanera', 'Artista')]!
          .affinity(Daypart.manana), 1);
      expect(Daypart.of(DateTime(2026, 1, 1, 23)), Daypart.noche);
      expect(Daypart.of(DateTime(2026, 1, 1, 3)), Daypart.madrugada);
    });
  });

  group('CommandParser.parseIntent', () {
    const p = CommandParser();

    test('cada frase de la gramática de Vosk es una orden', () {
      for (final phrase in CommandParser.voskGrammar) {
        if (phrase == '[unk]') continue;
        expect(p.parseIntent(phrase), isNotNull, reason: phrase);
      }
      expect(p.parseIntent('pon algo de'), isA<ArtistPromptIntent>());
      expect(p.parseIntent('cambia [unk]'), isNull);
    });

    test('pedidos naturales', () {
      expect(p.parseIntent('pon algo nuevo'), isA<DiscoverIntent>());
      expect(p.parseIntent('sorpréndeme'), isA<DiscoverIntent>());
      expect((p.parseIntent('pon algo de Ryan Castro') as ArtistIntent).artist,
          'ryan castro');
      final mood = p.parseIntent('pon algo para entrenar') as MoodIntent;
      expect(mood.query, contains('entrenar'));
      expect(p.parseIntent('pon algo de fiesta'), isA<MoodIntent>());
      expect(p.parseIntent('algo tranquilo'), isA<MoodIntent>());
    });

    test('órdenes nuevas', () {
      expect(p.parseIntent('Me gusta'), isA<LikeIntent>());
      expect(p.parseIntent('me encanta esta canción'), isA<LikeIntent>());
      expect(p.parseIntent('No me gusta'), isA<DislikeIntent>());
      expect(p.parseIntent('pon algo que me guste'), isA<FavoriteIntent>());
      expect(p.parseIntent('Busca'), isA<SearchPromptIntent>());
    });

    test('las de siempre siguen igual', () {
      expect((p.parseIntent('cambia') as CommandIntent).command, MusicCommand.next);
      expect((p.parseIntent('busca ojalá') as SearchIntent).request.query, 'ojala');
      expect(p.parseIntent('me gusta mucho esa película'), isNull);
    });
  });

  group('VoiceEngine', () {
    test('«me gusta» llega a onIntent', () {
      final intents = <VoiceIntent>[];
      final engine = VoiceEngine(
        onCommand: (_) async {},
        onIntent: (i) async => intents.add(i),
      );
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['me gusta']});
      expect(intents.single, isA<LikeIntent>());
    });

    test('audífonos: guarda el estado', () {
      final engine = VoiceEngine(onCommand: (_) async {});
      engine.handleEvent({'type': 'headphones', 'connected': true});
      expect(engine.headphonesConnected, isTrue);
      expect(engine.paused, isFalse, reason: 'sin escucha activa no pausa');
    });
  });

  group('AppSettings', () {
    test('recuerda ajustes y el último reproductor', () async {
      final store = MemoryJsonStore();
      final s1 = AppSettings(store: store);
      await s1.load();
      expect(s1.deviceId, hasLength(32));
      s1.update(onboardingDone: true, voiceFeedback: false);
      s1.lastUsedPlayerId = 'yt#1';
      await Future<void>.delayed(Duration.zero);

      final s2 = AppSettings(store: store);
      await s2.load();
      expect(s2.onboardingDone, isTrue);
      expect(s2.voiceFeedback, isFalse);
      expect(s2.lastUsedPlayerId, 'yt#1');
      expect(s2.deviceId, s1.deviceId);
    });
  });

  group('Solo mi voz', () {
    test('acepta tu voz y rechaza otra', () {
      final guard = SpeakerGuard(voiceprint: [1, 0, 0], enabled: true, threshold: 0.5);
      expect(guard.accepts([0.9, 0.1, 0]), isTrue);
      expect(guard.accepts([0, 1, 0]), isFalse);
      expect(guard.accepts(null), isTrue, reason: 'frase sin huella: no bloquear');
      guard.enabled = false;
      expect(guard.accepts([0, 1, 0]), isTrue);
    });

    test('entrenamiento: 3 frases y no ejecuta órdenes mientras tanto', () {
      final commands = <MusicCommand>[];
      List<double>? saved;
      final engine = VoiceEngine(onCommand: (c) async => commands.add(c));
      engine.startEnrollment((p) => saved = p);
      for (var i = 0; i < 3; i++) {
        engine.handleEvent({
          'type': 'final',
          'session': i,
          'texts': ['cambia'],
          'spk': [1.0, 0.0, i.toDouble()],
        });
      }
      expect(commands, isEmpty);
      expect(saved, isNotNull);
      expect(engine.enrolling, isFalse);
    });

    test('con «Solo mi voz» activo, otra voz no ejecuta', () {
      final commands = <MusicCommand>[];
      final engine = VoiceEngine(onCommand: (c) async => commands.add(c));
      engine.guard
        ..voiceprint = [1, 0, 0]
        ..enabled = true;
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['cambia'], 'spk': [0.0, 1.0, 0.0]});
      expect(commands, isEmpty);
      expect(engine.lastRejectedVoice, isTrue);
      engine.handleEvent({'type': 'final', 'session': 2, 'texts': ['cambia'], 'spk': [1.0, 0.1, 0.0]});
      expect(commands, [MusicCommand.next]);
    });
  });

  group('Palabra de activación', () {
    const p = CommandParser();

    test('«Oye música» es la palabra; después se acepta frase libre', () {
      expect(p.parseIntent('Oye música'), isA<WakeIntent>());
      expect(p.parseFree('cambia'), isA<CommandIntent>());
      final s = p.parseFree('busca ojalá de ryan castro') as SearchIntent;
      expect(s.request.query, 'ojala de ryan castro');
      // Cualquier otra cosa se toma como el nombre de la canción.
      expect((p.parseFree('Ojalá Ryan Castro') as SearchIntent).request.query,
          'Ojalá Ryan Castro');
      expect(p.parseFree('oye musica'), isNull);
    });

    test('con «Solo con Oye música», «cambia» suelto no hace nada', () {
      final commands = <MusicCommand>[];
      final engine = VoiceEngine(onCommand: (c) async => commands.add(c))
        ..requireWakeWord = true;
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['cambia']});
      expect(commands, isEmpty);
      engine.requireWakeWord = false;
      engine.handleEvent({'type': 'final', 'session': 2, 'texts': ['cambia']});
      expect(commands, [MusicCommand.next]);
    });
  });

  group('Perfil en la nube', () {
    test('unir canciones remotas se queda con el máximo y no duplica', () {
      final profile = MusicProfile();
      profile.mergeRemote([TrackStats(key: 'a|x', title: 'A', artist: 'X', likes: 2, plays: 5)]);
      profile.mergeRemote([TrackStats(key: 'a|x', title: 'A', artist: 'X', likes: 1, plays: 9)]);
      final t = profile.tracks['a|x']!;
      expect(t.likes, 2);
      expect(t.plays, 9);
      expect(profile.tracks.length, 1);
    });

    test('AppSettings guarda la sesión y los nuevos ajustes', () async {
      final store = MemoryJsonStore();
      final a = AppSettings(store: store);
      await a.load();
      a.update(wakeWord: true, headphoneTaps: false);
      a.setSession(email: 'j@x.co', userId: 'u1', accessToken: 't', refreshToken: 'r');
      final b = AppSettings(store: store);
      await b.load();
      expect(b.wakeWord, isTrue);
      expect(b.headphoneTaps, isFalse);
      expect(b.signedIn, isTrue);
      expect(b.authEmail, 'j@x.co');
      b.setSession();
      expect(b.signedIn, isFalse);
    });
  });

  group('20 mejoras: órdenes nuevas', () {
    const p = CommandParser();

    test('¿qué suena?, repite, adelanta, deshacer, compartir, radio', () {
      expect(p.parseIntent('¿Qué suena?'), isA<NowPlayingIntent>());
      expect(p.parseIntent('otra vez'), isA<RestartIntent>());
      expect((p.parseIntent('adelanta') as SeekIntent).seconds, 30);
      expect((p.parseIntent('atrasa') as SeekIntent).seconds, -30);
      expect(p.parseIntent('deshacer'), isA<UndoIntent>());
      expect(p.parseIntent('comparte esta'), isA<ShareIntent>());
      expect((p.parseIntent('pon mi radio') as RadioIntent).on, isTrue);
      expect((p.parseIntent('quita la radio') as RadioIntent).on, isFalse);
    });

    test('temporizador en palabras y números', () {
      expect((p.parseIntent('apaga en veinte minutos') as SleepIntent).minutes, 20);
      expect((p.parseIntent('apaga en 45 minutos') as SleepIntent).minutes, 45);
      expect((p.parseIntent('apaga en una hora') as SleepIntent).minutes, 60);
      expect((p.parseIntent('cancela el temporizador') as SleepIntent).minutes, 0);
      expect(p.parseSleep('apaga en mil minutos'), isNull);
    });

    test('escucha abierta: «pon …» sí, conversación no', () {
      final s = p.parseOpen('pon ojalá de ryan castro') as SearchIntent;
      expect(s.request.query, 'ojala de ryan castro');
      expect(p.parseOpen('cambia'), isA<CommandIntent>());
      expect(p.parseOpen('mañana voy a la casa de mi mamá'), isNull);
    });

    test('palabra de activación propia', () {
      CommandParser.customWakePhrases = {'hola amigo'};
      expect(p.parseIntent('Hola amigo'), isA<WakeIntent>());
      CommandParser.customWakePhrases = {};
      expect(p.parseIntent('hola amigo'), isNull);
    });
  });

  group('20 mejoras: perfil', () {
    test('repetir suma, racha de saltos y resumen semanal', () {
      var now = DateTime(2026, 11, 5, 20);
      final profile = MusicProfile(clock: () => now);
      profile.observe(playing('A'));
      profile.markRepeat();
      expect(profile.tracks.values.first.repeats, 1);

      // Tres saltos seguidos (cada uno antes de 30 s, tras «Cambia»).
      for (final t in ['B', 'C', 'D', 'E']) {
        profile.noteCommand(MusicCommand.next);
        now = now.add(const Duration(seconds: 10));
        profile.observe(playing(t));
      }
      expect(profile.recentSkipStreak(), greaterThanOrEqualTo(3));

      final s = profile.summary();
      expect(s.plays, 5);
      expect(s.playsPerDay.length, 7);
      expect(s.playsPerDaypart[Daypart.noche], 5);
    });
  });
}
