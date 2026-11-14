import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/assistant/smart_queue.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// PR #37: cola inteligente.
void main() {
  QueueItem q(String s, int? e, [String? artist]) => QueueItem(s, energy: e, artist: artist);
  List<String> names(List<QueueItem> l) => l.map((i) => i.query).toList();

  test('sin saltos bruscos: de lo tranquilo a lo movido, paso a paso', () {
    final items = [q('fiesta', 4), q('dormir', 0), q('alegre', 3), q('tranquila', 1)];
    final out = SmartQueue.arrange(items, startEnergy: 1);
    expect(names(out), ['tranquila', 'dormir', 'alegre', 'fiesta']);
    expect(SmartQueue.abruptJumps(items, startEnergy: 1), greaterThan(SmartQueue.abruptJumps(out, startEnergy: 1)));
  });

  test('evita el mismo artista dos veces seguidas', () {
    final items = [q('a1', 2, 'Feid'), q('a2', 2, 'Feid'), q('b1', 2, 'Karol G')];
    expect(names(SmartQueue.arrange(items, startEnergy: 2)), ['a1', 'b1', 'a2']);
  });

  test('si no sabe nada, no cambia el orden', () {
    final items = [q('x', null), q('y', null), q('z', null)];
    expect(names(SmartQueue.arrange(items)), ['x', 'y', 'z']);
  });

  test('palabras del nombre: acústico = tranquilo, remix = movido', () {
    expect(SmartQueue.energyFromWords('Tusa versión acústica'), 1);
    expect(SmartQueue.energyFromWords('Provenza Remix'), 4);
    expect(SmartQueue.energyFromWords('Ojalá'), isNull);
  });

  test('voz: «ordena la cola»', () {
    expect(const CommandParser().parseIntent('Ordena la cola'), isA<ArrangeQueueIntent>());
  });

  group('asistente', () {
    late Assistant a;
    late AppSettings settings;

    setUp(() {
      final lastUsed = InMemoryLastUsedStore();
      final connectors = ConnectorManager([FakeSource([])]);
      final detector = ActivePlayerDetector(lastUsed: lastUsed);
      final capabilities = CapabilityManager();
      final controller = DetectedPlayerController(
        connectors: connectors,
        detector: detector,
        capabilities: capabilities,
        router: CommandRouter(connectors: connectors, detector: detector, capabilities: capabilities, lastUsed: lastUsed),
      );
      final profile = MusicProfile();
      void add(String title, String artist, String mood) {
        final key = MusicProfile.keyFor(title, artist);
        profile.tracks[key] = TrackStats(key: key, title: title, artist: artist);
        (profile.moodTracks[mood] ??= <String>{}).add(key);
      }

      add('Calma', 'Pedro Capó', 'tranquila');
      add('Perreo', 'Feid', 'de fiesta');
      add('Feliz', 'Morat', 'alegre');
      settings = AppSettings();
      a = Assistant(controller: controller, profile: profile, settings: settings);
    });

    test('ordena con lo que sabe de tu música, explica y se puede deshacer', () {
      a.addToQueue(['Perreo Feid', 'Calma Pedro Capó', 'Feliz Morat']);
      final msg = a.arrangeQueue();
      expect(a.queue, ['Calma Pedro Capó', 'Feliz Morat', 'Perreo Feid']);
      expect(msg, startsWith('Ordené 3 canciones.'));
      expect(a.undoArrange(), isTrue);
      expect(a.queue, ['Perreo Feid', 'Calma Pedro Capó', 'Feliz Morat']);
    });

    test('sin datos de ambiente lo dice y no toca la cola', () {
      a.addToQueue(['Uno', 'Dos']);
      expect(a.arrangeQueue(), contains('Aún no sé el ambiente'));
      expect(a.queue, ['Uno', 'Dos']);
    });

    test('modo automático: ordena al agregar', () {
      settings.update(smartQueue: true);
      a.addToQueue(['Perreo Feid', 'Calma Pedro Capó', 'Feliz Morat']);
      expect(a.queue.first, 'Calma Pedro Capó');
    });
  });
}
