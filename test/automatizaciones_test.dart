import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/automations/automation.dart';
import 'package:smartbuds_ai/features/automations/automation_engine.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// Asistente que solo anota qué le pidieron.
class SpyAssistant extends Assistant {
  SpyAssistant(AppSettings s)
      : super(controller: _controller(), profile: MusicProfile(), settings: s);
  final seen = <VoiceIntent>[];

  static DetectedPlayerController _controller() {
    final lastUsed = InMemoryLastUsedStore();
    final connectors = ConnectorManager([FakeSource([])]);
    final detector = ActivePlayerDetector(lastUsed: lastUsed);
    final capabilities = CapabilityManager();
    return DetectedPlayerController(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      router: CommandRouter(connectors: connectors, detector: detector, capabilities: capabilities, lastUsed: lastUsed),
    );
  }

  @override
  Future<void> handleIntent(VoiceIntent intent) async => seen.add(intent);

  void connect(String? name) {
    headphoneName = name;
    notifyListeners();
  }
}

void main() {
  test('las plantillas son válidas y sus pasos se entienden', () {
    for (final t in automationTemplates(headphones: 'Buds')) {
      expect(t.validate(), isNull, reason: t.name);
    }
    for (final s in suggestedSteps) {
      expect(Automation.stepProblem(s), isNull, reason: s);
    }
  });

  test('valida frase, pasos y hora', () {
    final a = Automation(id: 'aaaaaaaa', name: 'X', kind: TriggerKind.phrase, phrase: 'gym', steps: ['volumen al 40']);
    expect(a.validate(), contains('dos palabras'));
    a.phrase = 'vamos al gym';
    expect(a.validate(), isNull);
    a.steps = ['haz magia por favor'];
    expect(a.validate(), contains('No entiendo'));
    a.steps = [];
    expect(a.validate(), contains('al menos un paso'));
    final t = Automation(id: 'bbbbbbbb', name: 'T', kind: TriggerKind.time, steps: ['pon algo nuevo']);
    expect(t.validate(), contains('hora'));
    t.minuteOfDay = 450;
    expect(t.validate(), isNull);
    expect(t.triggerLabel, contains('07:30'));
  });

  test('se guarda y se recupera (JSON)', () {
    final a = automationTemplates().first;
    final b = Automation.fromJson(a.toJson())!;
    expect(b.name, a.name);
    expect(b.steps, a.steps);
    expect(b.kind, a.kind);
    expect(Automation.fromJson({'kind': 'nada'}), isNull);
  });

  test('enlaces smartbuds:// solo permiten acciones conocidas', () {
    expect(AutomationEngine.actionForLink('smartbuds://accion/siguiente'), 'next');
    expect(AutomationEngine.actionForLink('smartbuds://accion/megusta'), 'like');
    expect(AutomationEngine.actionForLink('smartbuds://automatizacion/0a1b2c3d'), 'run:0a1b2c3d');
    expect(AutomationEngine.actionForLink('smartbuds://automatizacion/../../x'), isNull);
    expect(AutomationEngine.actionForLink('smartbuds://accion/borrar-todo'), isNull);
    expect(AutomationEngine.actionForLink('https://evil.com/accion/siguiente'), isNull);
  });

  group('motor', () {
    late AppSettings settings;
    late SpyAssistant assistant;
    late AutomationEngine engine;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 11, 16, 6, 59); // lunes
      settings = AppSettings();
      assistant = SpyAssistant(settings);
      engine = AutomationEngine(
        assistant: assistant,
        settings: settings,
        clock: () => now,
        stepDelay: Duration.zero,
        startTimer: false,
      );
    });

    test('tu frase tiene prioridad y ejecuta los pasos en orden', () async {
      final gym = Automation(
          id: Automation.newId(),
          name: 'Gimnasio',
          kind: TriggerKind.phrase,
          phrase: 'vamos al gimnasio',
          steps: ['volumen al 80', 'pon algo para entrenar']);
      expect(engine.save(gym), isNull);
      expect(settings.automations, hasLength(1));
      final intent = engine.match('Vamos al gimnasio');
      expect(intent, isA<MacroIntent>());
      expect(engine.match('vamos al cine'), isNull);
      await engine.runById((intent as MacroIntent).id);
      expect(assistant.seen.first, isA<VolumeIntent>());
      expect((assistant.seen.first as VolumeIntent).percent, 80);
      expect(assistant.seen.last, isA<MoodIntent>());
      expect(engine.lastRun[gym.id], now);
    });

    test('no deja dos con la misma frase', () {
      Automation mk() => Automation(
          id: Automation.newId(), name: 'A', kind: TriggerKind.phrase, phrase: 'buenas noches', steps: ['volumen al 20']);
      expect(engine.save(mk()), isNull);
      expect(engine.save(mk()), contains('esa frase'));
    });

    test('apagada no responde', () {
      final a = automationTemplates().first;
      engine.save(a);
      engine.toggle(a.id, false);
      expect(engine.match(a.phrase!), isNull);
    });

    test('al conectar los audífonos', () async {
      engine.save(Automation(
          id: Automation.newId(), name: 'Buds', kind: TriggerKind.headphones, device: 'Buds', steps: ['pon algo que me guste']));
      assistant.connect('Otros');
      await Future<void>.delayed(Duration.zero);
      expect(assistant.seen, isEmpty);
      assistant.connect('Buds');
      await Future<void>.delayed(Duration.zero);
      expect(assistant.seen.single, isA<FavoriteIntent>());
    });

    test('a una hora: una vez por día y solo los días elegidos', () async {
      final a = Automation(
          id: Automation.newId(),
          name: 'Mañana',
          kind: TriggerKind.time,
          minuteOfDay: 7 * 60,
          days: {1, 2, 3, 4, 5},
          steps: ['pon algo nuevo']);
      engine.save(a);
      await engine.tick();
      expect(assistant.seen, isEmpty); // 6:59
      now = DateTime(2026, 11, 16, 7, 0);
      await engine.tick();
      await engine.tick();
      expect(assistant.seen, hasLength(1));
      now = DateTime(2026, 11, 21, 7, 0); // sábado
      await engine.tick();
      expect(assistant.seen, hasLength(1));
    });
  });
}
