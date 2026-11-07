import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/devices/detected_player_screen.dart';

import 'fakes.dart';

DetectedPlayerController controllerFor(FakeSource source) {
  final lastUsed = InMemoryLastUsedStore();
  final connectors = ConnectorManager([source]);
  final detector = ActivePlayerDetector(lastUsed: lastUsed);
  final capabilities = CapabilityManager();
  return DetectedPlayerController(
    connectors: connectors,
    detector: detector,
    capabilities: capabilities,
    router: CommandRouter(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      lastUsed: lastUsed,
    ),
  );
}

Future<void> pumpScreen(WidgetTester tester, DetectedPlayerController c) async {
  await tester.pumpWidget(MaterialApp(home: DetectedPlayerScreen(controller: c)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin reproductores muestra «Ningún reproductor»', (tester) async {
    await pumpScreen(tester, controllerFor(FakeSource([])));
    expect(find.text('Reproductor detectado'), findsOneWidget);
    expect(find.text('Ningún reproductor'), findsOneWidget);
  });

  testWidgets('muestra el reproductor activo y el motivo', (tester) async {
    final yt = FakeConnector(status('YouTube Music', state: PlaybackState.playing));
    await pumpScreen(tester, controllerFor(FakeSource([yt])));
    expect(find.text('YouTube Music'), findsWidgets);
    expect(find.textContaining('Está reproduciendo audio'), findsOneWidget);
  });

  testWidgets('sin permiso muestra el aviso', (tester) async {
    await pumpScreen(
      tester,
      controllerFor(FakeSource([], permissionMessage: 'Activa el acceso')),
    );
    expect(find.text('Activa el acceso'), findsOneWidget);
  });
}
