import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = CommandParser();

  group('órdenes encadenadas', () {
    test('tres órdenes distintas con «y» y «luego»', () {
      final m = parser.parseIntent('siguiente y volumen al 30 y luego modo estudio');
      expect(m, isA<MultiIntent>());
      final parts = (m as MultiIntent).parts;
      expect(parts, hasLength(3));
      expect((parts[0] as CommandIntent).command, MusicCommand.next);
      expect((parts[1] as VolumeIntent).percent, 30);
      expect(parts[2], isA<UsageProfileIntent>());
    });

    test('«pon algo para entrenar y baja el volumen»', () {
      final m = parser.parseIntent('pon algo para entrenar y baja el volumen') as MultiIntent;
      expect(m.parts.first, isA<MoodIntent>());
      expect((m.parts.last as CommandIntent).command, MusicCommand.volumeDown);
    });

    test('un nombre con «y» no se parte', () {
      expect(parser.parseIntent('pon algo de feid y karol g'), isNot(isA<MultiIntent>()));
    });
  });

  test('«deja de escuchar»', () {
    expect(parser.parseIntent('Deja de escuchar'), isA<StopListeningIntent>());
  });

  group('estilo de respuesta', () {
    test('breve, conversacional y técnico', () {
      expect(VoiceEngine.styleReply('Reproduciendo Ojalá. Es de Ryan Castro.', ReplyStyle.brief),
          'Reproduciendo Ojalá.');
      expect(VoiceEngine.styleReply('Pongo algo tranquilo.', ReplyStyle.conversational), '¡Listo! Pongo algo tranquilo.');
      expect(VoiceEngine.styleReply('Pongo algo tranquilo.', ReplyStyle.conversational, n: 2),
          'Perfecto, pongo algo tranquilo.');
      expect(VoiceEngine.styleReply('Listo.', ReplyStyle.conversational), 'Listo.');
      expect(VoiceEngine.styleReply('Reproduciendo.', ReplyStyle.technical, action: 'Siguiente canción'),
          'Orden: Siguiente canción. Reproduciendo.');
      expect(VoiceEngine.styleReply('Hola.', ReplyStyle.normal), 'Hola.');
    });

    test('se guarda velocidad, tono y estilo', () {
      final s = AppSettings()..update(speechRate: 3, speechPitch: .8, replyStyle: 'technical');
      expect(s.speechRate, 2.0);
      expect(s.speechPitch, .8);
      expect(s.toMap()['replyStyle'], 'technical');
    });
  });

  test('una orden encadenada confirma una sola vez al final', () async {
    final spoken = <Map<dynamic, dynamic>>[];
    const channel = MethodChannel('smartbuds/voice-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as Map);
      return true;
    });
    late VoiceEngine engine;
    final intents = <VoiceIntent>[];
    engine = VoiceEngine(
      onCommand: (_) async => engine.speak('Siguiente canción.'),
      onIntent: (i) async {
        intents.add(i);
        await engine.speak('Volumen al 30.');
      },
      method: channel,
    )
      ..speechRate = 1.3
      ..speechPitch = .9;
    await engine.runChain(
      const [CommandIntent(MusicCommand.next), VolumeIntent(30)],
      gap: Duration.zero,
    );
    expect(intents.single, isA<VolumeIntent>());
    expect(engine.lastPlan, ['Siguiente canción', isNotEmpty]);
    expect(spoken, hasLength(1), reason: 'las respuestas de cada paso se juntan');
    expect(spoken.single['text'] as String, startsWith('Listo, hice 2 cosas: siguiente canción y '));
    expect(spoken.single['rate'], 1.3);
    expect(spoken.single['pitch'], .9);
  });
}
