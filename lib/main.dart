import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'connectors/android_media/android_media_connector.dart';
import 'connectors/connector_interface.dart';
import 'connectors/youtube/youtube_search.dart';
import 'core/capability_manager/capability_manager.dart';
import 'core/command_router/command_router.dart';
import 'core/connector_manager.dart';
import 'core/player_detector/active_player_detector.dart';
import 'core/settings/app_settings.dart';
import 'core/storage/json_store.dart';
import 'core/voice_engine/voice_engine.dart';
import 'features/assistant/assistant.dart';
import 'features/devices/detected_player_controller.dart';
import 'features/music_profile/music_profile.dart';
import 'features/music_profile/supabase_sync.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isAndroid = Platform.isAndroid;

  // Ajustes y perfil musical guardados en el teléfono.
  final settings = AppSettings(
      store: isAndroid ? FileJsonStore('settings.json') : MemoryJsonStore());
  await settings.load();

  final sync = SupabaseSync.fromEnvironment(settings.deviceId);
  final profile = MusicProfile(
    store: isAndroid ? FileJsonStore('music_profile.json') : MemoryJsonStore(),
    onEvent: sync == null ? null : (e, t) => sync.push(e, t),
  );
  await profile.load();

  runApp(SmartBudsApp(settings: settings, profile: profile, sync: sync));
}

class SmartBudsApp extends StatefulWidget {
  const SmartBudsApp({
    super.key,
    required this.settings,
    required this.profile,
    this.sync,
  });

  final AppSettings settings;
  final MusicProfile profile;
  final SupabaseSync? sync;

  @override
  State<SmartBudsApp> createState() => _SmartBudsAppState();
}

class _SmartBudsAppState extends State<SmartBudsApp> {
  late final AndroidMediaSource? android;
  late final DetectedPlayerController controller;
  late final Assistant assistant;
  VoiceEngine? voice;

  @override
  void initState() {
    super.initState();
    android = Platform.isAndroid ? AndroidMediaSource() : null;
    final sources = <PlayerSource>[if (android != null) android!];

    final finder = YouTubeSearch.fromEnvironment();
    final connectors = ConnectorManager(sources);
    // El último reproductor usado se recuerda entre sesiones (AppSettings).
    final detector = ActivePlayerDetector(lastUsed: widget.settings);
    final capabilities = CapabilityManager();
    final router = CommandRouter(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      lastUsed: widget.settings,
      volume: android,
      search: android,
      songFinder: finder,
    );
    controller = DetectedPlayerController(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      router: router,
    )..onActivePlayer = widget.profile.observe;

    assistant = Assistant(
      controller: controller,
      profile: widget.profile,
      finder: finder,
    );

    if (Platform.isAndroid) {
      final v = VoiceEngine(
        onCommand: assistant.handleCommand,
        onSearch: assistant.handleSearch,
        onIntent: assistant.handleIntent,
      )
        ..feedbackEnabled = widget.settings.voiceFeedback
        ..followHeadphones = widget.settings.followHeadphones
        ..attach(); // estado de audífonos desde el inicio
      v.guard
        ..voiceprint = widget.settings.voiceprint
        ..enabled = widget.settings.onlyMyVoice
        ..threshold = widget.settings.voiceThreshold;
      voice = v;
      assistant.voice = v;
      // Manos libres: si ya terminó la bienvenida, empieza a escuchar solo.
      if (widget.settings.onboardingDone) unawaited(v.autoStart());
    }
  }

  @override
  void dispose() {
    voice?.dispose();
    controller.dispose();
    widget.profile.dispose();
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
      home: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          if (!widget.settings.onboardingDone && Platform.isAndroid) {
            return OnboardingScreen(
              controller: controller,
              voice: voice,
              onOpenNotificationAccess: android?.openNotificationAccessSettings,
              onFinished: () => widget.settings.update(onboardingDone: true),
            );
          }
          return HomeShell(
            controller: controller,
            assistant: assistant,
            profile: widget.profile,
            settings: widget.settings,
            voice: voice,
            sync: widget.sync,
            onOpenNotificationAccess: android?.openNotificationAccessSettings,
            platformNote: Platform.isIOS
                ? 'iOS no permite detectar ni controlar reproductores de otras apps.'
                : null,
          );
        },
      ),
    );
  }
}
