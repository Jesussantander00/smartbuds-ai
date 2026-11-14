import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/diagnostics/self_check.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// PR #36: autodiagnóstico (voz, permisos, reproducción, conexión, audífonos).
void main() {
  final now = DateTime(2026, 11, 14, 11);

  Finding area(List<Finding> f, CheckArea a) => f.firstWhere((x) => x.area == a);

  test('todo bien: cada área en verde y el resumen lo dice', () {
    final f = SelfCheck.run(SelfCheckInput(
      now: now,
      micPermission: true,
      voiceEnabled: true,
      notificationAccess: true,
      playerApp: 'Spotify',
      online: true,
      headphones: 'Buds',
    ));
    expect(f.every((x) => x.isOk), isTrue);
    expect(SelfCheck.spokenSummary(f), 'Revisé todo y funciona bien.');
  });

  test('sin permiso de micrófono: problema con «Abrir ajustes»', () {
    final f = SelfCheck.run(SelfCheckInput(now: now, micPermission: false, voiceEnabled: true));
    final v = area(f, CheckArea.voz);
    expect(v.severity, Severity.problem);
    expect(v.action, FixAction.openAppSettings);
  });

  test('Jarvis caído: explica el error técnico en palabras simples y ofrece «Reintentar»', () {
    final f = SelfCheck.run(SelfCheckInput(
      now: now,
      micPermission: true,
      voiceEnabled: true,
      voiceFailed: true,
      voiceError: 'Mic busy: in use by another app',
    ));
    final v = area(f, CheckArea.voz);
    expect(v.title, 'Jarvis dejó de escuchar');
    expect(v.detail, 'Otra app está usando el micrófono.');
    expect(v.action, FixAction.retryVoice);
  });

  test('palabra de activación y «Solo mi voz» explican por qué «no responde»', () {
    final f = SelfCheck.run(SelfCheckInput(
      now: now,
      micPermission: true,
      voiceEnabled: true,
      requireWakeWord: true,
      onlyMyVoice: true,
      lastRejectedVoice: true,
    ));
    final titles = f.where((x) => x.area == CheckArea.voz).map((x) => x.title).toList();
    expect(titles, contains('Solo obedece después de «Oye música»'));
    expect(titles, contains('«Solo mi voz» ignoró la última frase'));
  });

  test('reproducción: la app no obedeció «siguiente» (solo errores recientes)', () {
    final f = SelfCheck.run(SelfCheckInput(
      now: now,
      voiceEnabled: true,
      playerApp: 'Spotify',
      errors: [
        (at: now.subtract(const Duration(minutes: 5)), kind: 'comando_next', message: 'timeout'),
        (at: now.subtract(const Duration(hours: 3)), kind: 'comando_pause', message: 'viejo'),
      ],
    ));
    final r = f.where((x) => x.area == CheckArea.reproduccion).single;
    expect(r.severity, Severity.problem);
    expect(r.title, contains('«siguiente»'));
  });

  test('sin internet: dice qué sigue funcionando y qué no', () {
    final f = SelfCheck.run(SelfCheckInput(now: now, online: false));
    final c = area(f, CheckArea.conexion);
    expect(c.severity, Severity.problem);
    expect(c.detail, contains('siguen funcionando'));
  });

  test('sin datos de conexión no inventa un resultado', () {
    final f = SelfCheck.run(SelfCheckInput(now: now));
    expect(f.where((x) => x.area == CheckArea.conexion), isEmpty);
  });

  test('resumen hablado: problemas primero, máximo tres', () {
    final f = SelfCheck.run(SelfCheckInput(
      now: now,
      micPermission: false,
      notificationAccess: false,
      online: false,
      unstableHeadphones: true,
    ));
    final s = SelfCheck.spokenSummary(f);
    expect(s, startsWith('Encontré 4 problemas: falta el permiso de micrófono'));
    expect(';'.allMatches(s).length, 2, reason: 'solo tres cosas');
  });

  test('voz: «haz un diagnóstico» y «¿qué te pasa?»', () {
    const p = CommandParser();
    expect(p.parseIntent('Haz un diagnóstico'), isA<DiagnoseIntent>());
    expect(p.parseIntent('¿Qué te pasa?'), isA<DiagnoseIntent>());
  });

  test('el asistente junta los datos reales del teléfono', () async {
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
    final a = Assistant(controller: controller, profile: MusicProfile(), settings: AppSettings())
      ..onlineProbe = (() async => false)
      ..headphoneName = 'Buds';
    final f = await a.selfCheck();
    expect(area(f, CheckArea.conexion).severity, Severity.problem);
    expect(area(f, CheckArea.audifonos).isOk, isTrue);
    expect(area(f, CheckArea.reproduccion).title, 'No hay app de música abierta');
    expect(area(f, CheckArea.voz).title, 'La voz de Jarvis no está en esta versión');
  });
}
