import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';

void main() {
  group('CommandParser', () {
    const p = CommandParser();

    test('comandos básicos', () {
      expect(p.parse('Cambia'), MusicCommand.next);
      expect(p.parse('cámbiala'), MusicCommand.next);
      expect(p.parse('otra canción'), MusicCommand.next);
      expect(p.parse('Devuelve'), MusicCommand.previous);
      expect(p.parse('pausa'), MusicCommand.pause);
      expect(p.parse('Continúa'), MusicCommand.play);
      expect(p.parse('sube'), MusicCommand.volumeUp);
      expect(p.parse('baja el volumen'), MusicCommand.volumeDown);
    });

    test('dentro de una frase más larga', () {
      expect(p.parse('oye cambia esa'), MusicCommand.next);
      expect(p.parse('ponla en pausa por favor'), MusicCommand.pause);
    });

    test('mayúsculas, tildes y signos', () {
      expect(p.parse('¡CAMBIA!'), MusicCommand.next);
      expect(p.parse('  Continúa.  '), MusicCommand.play);
    });

    test('conversación normal no dispara comandos', () {
      expect(p.parse('voy para la casa'), isNull);
      expect(p.parse('hola cómo estás'), isNull);
      expect(p.parse(''), isNull);
    });

    test('«me gusta» y «no me gusta» quedan reservados', () {
      expect(p.parse('me gusta'), isNull);
      expect(p.parse('no me gusta, cambia'), isNull);
    });
  });

  group('CommandParser.parseExact (modo voz)', () {
    const p = CommandParser();

    test('solo la orden sola cuenta', () {
      expect(p.parseExact('Cambia'), MusicCommand.next);
      expect(p.parseExact('otra canción'), MusicCommand.next);
      expect(p.parseExact('sube'), MusicCommand.volumeUp);
      expect(p.parseExact('baja'), MusicCommand.volumeDown);
    });

    test('hablar o cantar con comandos en medio no cuenta', () {
      expect(p.parseExact('siguiente otra pasa reproduce'), isNull);
      expect(p.parseExact('oye cambia esa'), isNull);
      expect(p.parseExact('sube sube sube'), isNull);
    });
  });

  group('VoiceEngine', () {
    late List<MusicCommand> sent;
    late VoiceEngine engine;
    late DateTime now;

    setUp(() {
      sent = [];
      now = DateTime(2026, 11, 7, 15);
      engine = VoiceEngine(onCommand: (c) async => sent.add(c), clock: () => now);
    });

    test('parcial y final de la misma frase ejecutan una sola vez', () {
      engine.handleEvent({'type': 'partial', 'session': 1, 'texts': ['cambia']});
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['cambia']});
      expect(sent, [MusicCommand.next]);
      expect(engine.lastHeard, 'cambia');
    });

    test('la misma orden repetida enseguida se ignora (eco del reconocedor)', () {
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['cambia']});
      now = now.add(const Duration(milliseconds: 800));
      engine.handleEvent({'type': 'final', 'session': 2, 'texts': ['cambia']});
      expect(sent, [MusicCommand.next]);
      now = now.add(const Duration(seconds: 3));
      engine.handleEvent({'type': 'final', 'session': 3, 'texts': ['cambia']});
      expect(sent, [MusicCommand.next, MusicCommand.next]);
    });

    test('frases distintas ejecutan comandos distintos', () {
      engine.handleEvent({'type': 'final', 'session': 1, 'texts': ['cambia']});
      engine.handleEvent({'type': 'final', 'session': 2, 'texts': ['pausa']});
      expect(sent, [MusicCommand.next, MusicCommand.pause]);
    });

    test('usa la alternativa si la primera no es un comando', () {
      engine.handleEvent({
        'type': 'final',
        'session': 3,
        'texts': ['campiña', 'cambia'],
      });
      expect(sent, [MusicCommand.next]);
    });

    test('el ruido se muestra pero no ejecuta nada', () {
      engine.handleEvent({'type': 'noise', 'session': 1, 'texts': ['… cambia …']});
      expect(sent, isEmpty);
      expect(engine.lastHeard, '… cambia …');
    });

    test('estado de escucha y errores', () {
      engine.handleEvent({'type': 'state', 'session': 1, 'listening': true});
      expect(engine.listening, isTrue);
      engine.handleEvent({'type': 'error', 'session': 1, 'message': 'fallo'});
      expect(engine.error, 'fallo');
    });
  });
}
