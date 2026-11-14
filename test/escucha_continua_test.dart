import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';

/// Pruebas del ciclo de escucha continua (PR #34): la parte de Dart. El lado
/// nativo (Vosk en Android, Apple Speech en iPhone) se prueba en teléfonos reales.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartbuds/voice-cycle-test');
  late List<String> calls;
  late bool failStart;
  late DateTime now;
  late List<MusicCommand> commands;
  late List<VoiceIntent> intents;
  late VoiceEngine v;

  setUp(() {
    calls = [];
    failStart = false;
    now = DateTime(2026, 11, 14, 9);
    commands = [];
    intents = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isAvailable':
        case 'requestPermission':
        case 'hasPermission':
          return true;
        case 'start':
          if (failStart) throw PlatformException(code: 'PERMISSION');
          return true;
        default:
          return true;
      }
    });
    v = VoiceEngine(
      onCommand: (c) async => commands.add(c),
      onIntent: (i) async => intents.add(i),
      onSearch: (_) async {},
      clock: () => now,
      method: channel,
    );
  });

  tearDown(() => v.dispose());

  void hear(String text, int session) {
    v.handleEvent({'type': 'final', 'texts': [text], 'session': session});
    now = now.add(const Duration(seconds: 4)); // más que el tiempo anti-repetición
  }

  test('al entrar con permiso: escucha sola (sin tocar el micrófono)', () async {
    await v.autoStart();
    expect(v.enabled, isTrue);
    expect(calls, contains('start'));
    v.handleEvent({'type': 'state', 'listening': true});
    expect(v.jarvisState, JarvisState.listening);
  });

  test('cinco órdenes seguidas, cada una en su frase, se ejecutan todas', () async {
    await v.start();
    v.handleEvent({'type': 'state', 'listening': true});
    hear('cambia', 0);
    hear('pausa', 1);
    hear('sube', 2);
    hear('cambia', 3);
    hear('baja', 4);
    expect(commands, [
      MusicCommand.next,
      MusicCommand.pause,
      MusicCommand.volumeUp,
      MusicCommand.next,
      MusicCommand.volumeDown,
    ]);
    expect(v.jarvisState, isNot(JarvisState.error));
  });

  test('la misma frase (parcial + final) no se ejecuta dos veces', () async {
    await v.start();
    v.handleEvent({'type': 'final', 'texts': ['cambia'], 'session': 7});
    v.handleEvent({'type': 'final', 'texts': ['cambia'], 'session': 7});
    expect(commands, hasLength(1));
  });

  test('después de que Jarvis responde, acepta la siguiente orden', () async {
    await v.start();
    v.handleEvent({'type': 'state', 'listening': true});
    hear('cambia', 0);
    v.handleEvent({'type': 'speaking', 'on': true});
    expect(v.jarvisState, JarvisState.responding);
    v.handleEvent({'type': 'speaking', 'on': false});
    hear('pausa', 1);
    expect(commands, hasLength(2));
  });

  group('vigilante (recuperación sin reintentos infinitos)', () {
    test('si se cae en silencio, reabre el micrófono tras 8 s', () async {
      await v.start();
      v.handleEvent({'type': 'state', 'listening': false});
      calls.clear();
      await v.checkHealth();
      expect(calls, isNot(contains('ensure')), reason: 'todavía dentro de la tolerancia');
      now = now.add(const Duration(seconds: 9));
      await v.checkHealth();
      expect(calls, contains('ensure'));
      expect(v.jarvisState, JarvisState.recovering);
      v.handleEvent({'type': 'state', 'listening': true});
      expect(v.jarvisState, JarvisState.listening);
    });

    test('con pausas crecientes y, si no se recupera, pasa a error con «Reintentar»', () async {
      await v.start();
      v.handleEvent({'type': 'state', 'listening': false});
      var ensures = 0;
      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(seconds: 4));
        calls.clear();
        await v.checkHealth();
        ensures += calls.where((c) => c == 'ensure').length;
      }
      expect(ensures, VoiceEngine.maxRecoverAttempts, reason: 'no reintenta sin fin');
      expect(v.jarvisState, JarvisState.error);
      expect(v.error, contains('Reintentar'));
      calls.clear();
      await v.retry();
      expect(calls, contains('ensure'));
      expect(v.failed, isFalse);
    });

    test('no interviene en pausa, mientras habla ni esperando una canción', () async {
      await v.start();
      v.handleEvent({'type': 'state', 'listening': false});
      v.speaking = true;
      now = now.add(const Duration(seconds: 30));
      calls.clear();
      await v.checkHealth();
      expect(calls, isEmpty);
    });
  });

  test('error del teléfono sin solución (fatal): estado error hasta que vuelva a escuchar', () async {
    await v.start();
    v.handleEvent({'type': 'error', 'message': 'El micrófono no responde', 'fatal': true});
    expect(v.jarvisState, JarvisState.error);
    v.handleEvent({'type': 'state', 'listening': true});
    expect(v.jarvisState, JarvisState.listening);
  });

  test('detener (botón o «deja de escuchar») apaga todo', () async {
    await v.start();
    await v.stop();
    expect(v.jarvisState, JarvisState.off);
    expect(calls, contains('stop'));
    await v.start();
    v.handleEvent({'type': 'final', 'texts': ['deja de escuchar'], 'session': 1});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(v.enabled, isFalse);
  });

  test('sin permiso: avisa claro y no queda «escuchando» a medias', () async {
    failStart = true;
    await v.start();
    expect(v.enabled, isFalse);
    expect(v.error, contains('permiso'));
  });

  test('detenido desde la notificación: queda apagado', () async {
    await v.start();
    v.handleEvent({'type': 'state', 'listening': false, 'stopped': true});
    expect(v.jarvisState, JarvisState.off);
  });

  test('registro de diagnóstico de la escucha', () async {
    await v.start();
    v.handleEvent({'type': 'state', 'listening': true});
    v.handleEvent({'type': 'error', 'message': 'X'});
    final what = v.diagnostics.map((d) => d.what).join(' | ');
    expect(what, contains('Escucha continua activada'));
    expect(what, contains('Escuchando'));
    expect(what, contains('Error: X'));
  });
}
