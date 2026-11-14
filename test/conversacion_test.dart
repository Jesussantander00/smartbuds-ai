import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/storage/json_store.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';

/// PR #35: memoria de conversación, órdenes incompletas, correcciones e historial.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartbuds/voice-conversation-test');
  const p = CommandParser();
  late List<String> spoken;
  late String? answer; // lo que «dice» el usuario tras una pregunta
  late DateTime now;
  late List<MusicCommand> commands;
  late List<VoiceIntent> intents;
  late VoiceEngine v;
  String? playing;
  var private = false;

  setUp(() {
    spoken = [];
    answer = null;
    playing = null;
    private = false;
    now = DateTime(2026, 11, 14, 10);
    commands = [];
    intents = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') spoken.add((call.arguments as Map)['text'] as String);
      if (call.method == 'listenOnce') return answer;
      return true;
    });
    v = VoiceEngine(
      onCommand: (c) async => commands.add(c),
      onIntent: (i) async => intents.add(i),
      onSearch: (_) async {},
      clock: () => now,
      method: channel,
    )
      ..currentArtist = (() => playing)
      ..isPrivate = (() => private);
  });

  tearDown(() => v.dispose());

  Future<void> hear(String text, int session) async {
    v.handleEvent({'type': 'final', 'texts': [text], 'session': session});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    now = now.add(const Duration(seconds: 4));
  }

  group('el parser reconoce las frases nuevas', () {
    test('seguimiento, corrección e incompletas', () {
      expect(p.parseIntent('pon una de él'), isA<FollowUpArtistIntent>());
      expect(p.parseIntent('otra del mismo artista'), isA<FollowUpArtistIntent>());
      expect(p.parseIntent('No, la otra'), isA<CorrectionIntent>());
      expect(p.parseIntent('eso no era'), isA<CorrectionIntent>());
      expect(p.parseIntent('pon'), isA<ClarifyIntent>());
      expect(p.parseIntent('quiero escuchar'), isA<ClarifyIntent>());
      expect(p.parseIntent('pon algo de'), isA<ArtistPromptIntent>(), reason: 'se mantiene');
      expect((p.parseIntent('algo más movido') as MoodIntent).mood, 'con energía');
      // No rompe pedidos completos.
      expect((p.parseIntent('pon algo de Feid') as ArtistIntent).artist, 'feid');
      expect(p.parseIntent('no me gusta'), isA<DislikeIntent>());
    });
  });

  group('memoria de conversación', () {
    test('«busca Feid» → «pon una de él» usa el artista que suena', () async {
      playing = 'Feid';
      await hear('pon una de él', 1);
      expect(intents.whereType<ArtistIntent>().single.artist, 'Feid');
    });

    test('sin música: recuerda el artista del que hablaron', () async {
      await hear('pon algo de Karol G', 1);
      await hear('otra de ella', 2);
      final artists = intents.whereType<ArtistIntent>().map((a) => a.artist).toList();
      expect(artists, ['karol g', 'karol g']);
    });

    test('el contexto caduca a los 10 minutos: entonces pregunta «¿De quién?»', () async {
      await hear('pon algo de Karol G', 1);
      now = now.add(const Duration(minutes: 11));
      answer = 'Feid';
      await hear('pon una de él', 2);
      expect(spoken, contains('¿De quién?'));
      expect(intents.whereType<ArtistIntent>().last.artist, 'Feid');
    });
  });

  group('órdenes incompletas', () {
    test('«pon» pregunta qué artista o género y usa la respuesta', () async {
      answer = 'algo tranquilo';
      await hear('pon', 1);
      expect(spoken.first, contains('artista o género'));
      expect(intents.last, isA<MoodIntent>());
    });

    test('si respondes un artista, lo busca', () async {
      answer = 'Ryan Castro';
      await hear('quiero escuchar', 1);
      expect((intents.last as SearchIntent).request.query, 'Ryan Castro');
    });
  });

  group('corrección inteligente', () {
    test('«cambia» → «no, la otra» vuelve a la anterior', () async {
      await hear('cambia', 1);
      await hear('no, la otra', 2);
      expect(commands, [MusicCommand.next, MusicCommand.previous]);
    });

    test('«sube» → «eso no era» baja', () async {
      await hear('sube', 1);
      await hear('eso no era', 2);
      expect(commands, [MusicCommand.volumeUp, MusicCommand.volumeDown]);
    });

    test('tras una búsqueda pregunta qué querías y busca eso', () async {
      await hear('pon algo de Feid', 1);
      answer = 'Blessd';
      await hear('esa no', 2);
      expect(spoken.any((s) => s.contains('¿Qué querías escuchar?')), isTrue);
      expect((intents.last as SearchIntent).request.query, 'Blessd');
    });

    test('sin nada reciente, lo dice en vez de inventar', () async {
      await hear('no, la otra', 1);
      expect(spoken.single, contains('nada reciente'));
      expect(commands, isEmpty);
    });

    test('pasado el tiempo ya no corrige', () async {
      await hear('cambia', 1);
      now = now.add(const Duration(minutes: 3));
      await hear('no, la otra', 2);
      expect(commands, [MusicCommand.next]);
    });
  });

  group('historial de conversaciones', () {
    test('guarda orden y respuesta, se carga y se borra', () async {
      final store = MemoryJsonStore();
      v.historyStore = store;
      await hear('cambia', 1);
      await v.speak('Listo');
      await Future<void>.delayed(Duration.zero);
      final saved = (store.data!['entries'] as List).first as Map;
      expect(saved['action'], 'Siguiente canción');
      expect(saved['reply'], isNotNull);

      final other = VoiceEngine(onCommand: (_) async {}, method: channel)..historyStore = store;
      await other.loadHistory();
      expect(other.history.single.heard, 'cambia');
      other.dispose();

      await v.clearHistory();
      expect(v.history, isEmpty);
      expect(store.data!['entries'], isEmpty);
      expect(v.conversation.lastAction, isNull);
    });

    test('en modo privado no se guarda lo que dices (pero la orden se cumple)', () async {
      private = true;
      await hear('cambia', 1);
      expect(v.history, isEmpty);
      expect(commands, [MusicCommand.next]);
    });
  });
}
