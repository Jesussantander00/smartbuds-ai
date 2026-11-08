import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connectors/android_media/android_media_connector.dart';
import 'connectors/connector_interface.dart';
import 'connectors/deezer/similar_artists.dart';
import 'connectors/youtube/youtube_search.dart';
import 'core/capability_manager/capability_manager.dart';
import 'core/command_router/command_router.dart';
import 'core/connector_manager.dart';
import 'core/models.dart';
import 'core/player_detector/active_player_detector.dart';
import 'core/settings/app_settings.dart';
import 'core/storage/json_store.dart';
import 'core/voice_engine/voice_engine.dart';
import 'features/account/supabase_auth.dart';
import 'features/assistant/assistant.dart';
import 'features/devices/detected_player_controller.dart';
import 'features/music_profile/music_profile.dart';
import 'features/music_profile/supabase_sync.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android e iPhone guardan en un archivo propio de la app (sobrevive al cierre).
  final isNative = Platform.isAndroid || Platform.isIOS;

  // Ajustes y perfil musical guardados en el teléfono.
  final settings = AppSettings(
      store: isNative ? FileJsonStore('settings.json') : MemoryJsonStore());
  await settings.load();

  // Cuenta (opcional): solo si Supabase está configurado en secrets.json.
  final auth = SupabaseSync.configured
      ? SupabaseAuth(
          url: SupabaseSync.envUrl, anonKey: SupabaseSync.envKey, settings: settings)
      : null;
  final sync = SupabaseSync.fromEnvironment(settings.deviceId, auth: auth);
  final profile = MusicProfile(
    store: isNative ? FileJsonStore('music_profile.json') : MemoryJsonStore(),
    onEvent: sync == null ? null : (e, t) => sync.push(e, t),
  );
  await profile.load();

  // Al entrar a la cuenta: trae tus gustos de la nube y sube los de este teléfono.
  auth?.onSignedIn = () async {
    if (sync == null) return;
    try {
      profile.mergeRemote(await sync.pullScores());
    } catch (_) {}
    await sync.pushAll(profile);
  };

  runApp(SmartBudsApp(settings: settings, profile: profile, sync: sync, auth: auth));
}

class SmartBudsApp extends StatefulWidget {
  const SmartBudsApp({
    super.key,
    required this.settings,
    required this.profile,
    this.sync,
    this.auth,
  });

  final AppSettings settings;
  final MusicProfile profile;
  final SupabaseSync? sync;
  final SupabaseAuth? auth;

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
    // Mismo canal nativo en las dos plataformas: Android (MediaSession) e
    // iPhone (Apple Music, ver ios/Runner/AppDelegate.swift).
    android = (Platform.isAndroid || Platform.isIOS) ? AndroidMediaSource() : null;
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
      searchPackage: Platform.isIOS ? 'com.apple.Music' : CommandRouter.defaultSearchPackage,
      searchAppName: Platform.isIOS ? 'Apple Music' : 'YouTube Music',
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
      similar: DeezerSimilarArtists(),
    );

    if (Platform.isAndroid || Platform.isIOS) {
      final v = VoiceEngine(
        onCommand: assistant.handleCommand,
        onSearch: assistant.handleSearch,
        onIntent: assistant.handleIntent,
      )
        ..feedbackEnabled = widget.settings.voiceFeedback
        ..followHeadphones = widget.settings.followHeadphones
        ..requireWakeWord = widget.settings.wakeWord
        ..attach(); // estado de audífonos desde el inicio
      v.guard
        ..voiceprint = widget.settings.voiceprint
        ..enabled = widget.settings.onlyMyVoice
        ..threshold = widget.settings.voiceThreshold;
      voice = v;
      assistant.voice = v;
      unawaited(android?.setTapGestures(widget.settings.headphoneTaps));
      _listenForShortcuts();
      // Manos libres: si ya terminó la bienvenida, empieza a escuchar solo.
      if (widget.settings.onboardingDone) unawaited(v.autoStart());
    }
  }

  /// Accesos rápidos del ícono (mantener presionado) y botones del widget.
  void _listenForShortcuts() {
    const channel = MethodChannel('smartbuds/actions');
    channel.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      switch (call.arguments as String?) {
        case 'listen':
          if (voice?.enabled == false) await voice?.start();
        case 'next':
          await assistant.handleCommand(MusicCommand.next);
        case 'favorite':
          await assistant.playFavorite();
        case 'discover':
          await assistant.discover();
      }
    });
    unawaited(channel.invokeMethod('ready').catchError((_) => null));
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
          // Bienvenida en las dos plataformas: la escucha solo arranca sola
          // cuando ya se terminó (misma condición en Android e iPhone).
          if (!widget.settings.onboardingDone && (Platform.isAndroid || Platform.isIOS)) {
            return OnboardingScreen(
              controller: controller,
              voice: voice,
              onOpenNotificationAccess:
                  Platform.isIOS ? null : android?.openNotificationAccessSettings,
              onRequestMusicAccess: Platform.isIOS ? android?.requestMusicAccess : null,
              hasMusicAccess: Platform.isIOS ? android?.hasMusicAccess : null,
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
            auth: widget.auth,
            onHeadphoneTapsChanged: android?.setTapGestures,
            onOpenNotificationAccess: android?.openNotificationAccessSettings,
            platformNote: Platform.isIOS
                ? 'En iPhone, SmartBuds controla Apple Music. iOS no deja controlar '
                    'otras apps (YouTube Music, Spotify…).'
                : null,
          );
        },
      ),
    );
  }
}
