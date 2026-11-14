import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';
import 'package:smartbuds_ai/features/diagnostics/self_check.dart';

/// PR #38: la música conserva su volumen mientras Jarvis escucha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartbuds/voice-volume-test');
  late List<MethodCall> calls;
  late DateTime now;
  late List<MusicCommand> commands;
  late VoiceEngine v;

  setUp(() {
    calls = [];
    now = DateTime(2026, 11, 14, 12);
    commands = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    v = VoiceEngine(onCommand: (c) async => commands.add(c), clock: () => now, method: channel);
  });

  tearDown(() => v.dispose());

  Future<void> hear(String text, int session, {int seconds = 4}) async {
    v.handleEvent({'type': 'final', 'texts': [text], 'session': session});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    now = now.add(Duration(seconds: seconds));
  }

  test('«sube» y «baja» seguidos (conversación o canto) no hacen subir y bajar la música', () async {
    await hear('sube', 1);
    await hear('baja', 2);
    await hear('sube', 3);
    expect(commands, [MusicCommand.volumeUp]);
    expect(v.ignoredVolumeFlips, 2);
    expect(v.diagnostics.first.what, contains('parece conversación o canto'));
  });

  test('la frase completa sí cambia el volumen aunque sea contraria', () async {
    await hear('sube', 1);
    await hear('baja el volumen', 2);
    expect(commands, [MusicCommand.volumeUp, MusicCommand.volumeDown]);
  });

  test('pasado el tiempo, la orden contraria se obedece', () async {
    await hear('sube', 1, seconds: 12);
    await hear('baja', 2);
    expect(commands, [MusicCommand.volumeUp, MusicCommand.volumeDown]);
  });

  test('la misma dirección varias veces funciona (subir de a poco)', () async {
    await hear('sube', 1);
    await hear('sube', 2);
    expect(commands, [MusicCommand.volumeUp, MusicCommand.volumeUp]);
  });

  test('las demás órdenes no se afectan', () async {
    await hear('sube', 1);
    await hear('cambia', 2);
    expect(commands, [MusicCommand.volumeUp, MusicCommand.next]);
  });

  test('bajar la música al responder: solo si está activado, y se avisa al teléfono', () async {
    await v.speak('Listo');
    expect((calls.lastWhere((c) => c.method == 'speak').arguments as Map)['duck'], isFalse);
    v.duckOnReply = true;
    await v.speak('Listo');
    expect((calls.lastWhere((c) => c.method == 'speak').arguments as Map)['duck'], isTrue);
  });

  test('los avisos de audio del teléfono quedan en el registro', () {
    v.handleEvent({'type': 'audio', 'event': 'restart_blocked', 'why': 'route'});
    v.handleEvent({'type': 'audio', 'event': 'duck_on'});
    final what = v.diagnostics.map((d) => d.what).join(' | ');
    expect(what, contains('Evité un ciclo de reinicios del micrófono (route)'));
    expect(what, contains('Bajé la música mientras Jarvis responde'));
  });

  test('el autodiagnóstico explica las órdenes de volumen ignoradas', () {
    final f = SelfCheck.run(SelfCheckInput(now: now, micPermission: true, voiceEnabled: true, ignoredVolumeFlips: 2));
    expect(f.any((x) => x.title.startsWith('Ignoré 2 órdenes de volumen')), isTrue);
  });
}
