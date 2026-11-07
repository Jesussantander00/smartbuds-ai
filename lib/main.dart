import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'connectors/android_media/android_media_connector.dart';
import 'connectors/connector_interface.dart';
import 'core/capability_manager/capability_manager.dart';
import 'core/command_router/command_router.dart';
import 'core/connector_manager.dart';
import 'core/player_detector/active_player_detector.dart';
import 'features/devices/detected_player_controller.dart';
import 'features/devices/detected_player_screen.dart';

void main() => runApp(const SmartBudsApp());

class SmartBudsApp extends StatefulWidget {
  const SmartBudsApp({super.key});

  @override
  State<SmartBudsApp> createState() => _SmartBudsAppState();
}

class _SmartBudsAppState extends State<SmartBudsApp> {
  late final AndroidMediaSource? android;
  late final DetectedPlayerController controller;

  @override
  void initState() {
    super.initState();
    android = Platform.isAndroid ? AndroidMediaSource() : null;

    // Fase 4 añadirá aquí AppleMusicSource (iOS y Android) y el reproductor propio.
    final sources = <PlayerSource>[if (android != null) android!];

    final lastUsed = InMemoryLastUsedStore();
    final connectors = ConnectorManager(sources);
    final detector = ActivePlayerDetector(lastUsed: lastUsed);
    final capabilities = CapabilityManager();
    final router = CommandRouter(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      lastUsed: lastUsed,
      volume: android,
    );
    controller = DetectedPlayerController(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      router: router,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartBuds AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00B4D8),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: DetectedPlayerScreen(
        controller: controller,
        onOpenPermissions: android?.openNotificationAccessSettings,
        platformNote: Platform.isIOS
            ? 'iOS no permite detectar ni controlar reproductores de otras apps. '
                'El conector de Apple Music (MusicKit) llega en la Fase 4.'
            : null,
      ),
    );
  }
}
