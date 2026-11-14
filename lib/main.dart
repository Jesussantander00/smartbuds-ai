import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connectors/android_media/android_media_connector.dart';
import 'connectors/connector_interface.dart';
import 'connectors/deezer/similar_artists.dart';
import 'connectors/weather/weather.dart';
import 'connectors/youtube/youtube_search.dart';
import 'core/capability_manager/capability_manager.dart';
import 'core/command_router/command_router.dart';
import 'core/connector_manager.dart';
import 'core/models.dart';
import 'core/player_detector/active_player_detector.dart';
import 'core/settings/app_settings.dart';
import 'core/storage/json_store.dart';
import 'core/voice_engine/command_parser.dart';
import 'core/voice_engine/voice_engine.dart';
import 'core/telemetry/error_reporter.dart';
import 'core/ui/futuristic.dart';
import 'features/account/supabase_auth.dart';
import 'features/assistant/assistant.dart';
import 'connectors/knowledge/music_knowledge.dart';
import 'features/audio/eq_controller.dart';
import 'features/audio/transition_watcher.dart';
import 'features/automations/automation_engine.dart';
import 'features/smarthome/home_link.dart';
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

  // Reportes anónimos de errores (se pueden apagar en Ajustes).
  final errors = SupabaseSync.configured
      ? ErrorReporter(
          url: SupabaseSync.envUrl,
          anonKey: SupabaseSync.envKey,
          deviceId: settings.deviceId,
          enabled: () => settings.errorReports,
        )
      : null;
  if (errors != null) {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(errors.report('flutter', details.exceptionAsString()));
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(errors.report('sin_capturar', error));
      return false;
    };
  }

  runApp(SmartBudsApp(
      settings: settings, profile: profile, sync: sync, auth: auth, errors: errors));
}

class SmartBudsApp extends StatefulWidget {
  const SmartBudsApp({
    super.key,
    required this.settings,
    required this.profile,
    this.sync,
    this.auth,
    this.errors,
  });

  final AppSettings settings;
  final MusicProfile profile;
  final SupabaseSync? sync;
  final SupabaseAuth? auth;
  final ErrorReporter? errors;

  @override
  State<SmartBudsApp> createState() => _SmartBudsAppState();
}

class _SmartBudsAppState extends State<SmartBudsApp> {
  late final AndroidMediaSource? android;
  late final DetectedPlayerController controller;
  late final Assistant assistant;
  late final AutomationEngine automations;
  TransitionWatcher? transitions;
  String? _homeTrack, _homeMood;

  /// Avisos al hogar inteligente: cada canción nueva y cada cambio de ambiente.
  void _notifyHome(PlayerStatus? s) {
    final home = assistant.home;
    if (home == null || widget.settings.homeHooks.isEmpty) return;
    if (s != null && s.isPlaying && s.title != null && s.trackKey != _homeTrack) {
      _homeTrack = s.trackKey;
      unawaited(home.notify('track', title: s.title, artist: s.artist, mood: widget.profile.currentMood));
    }
    final mood = assistant.brain.ambience()?.mood;
    if (mood != null && mood != _homeMood) {
      _homeMood = mood;
      unawaited(home.notify('mood', title: s?.title, artist: s?.artist, mood: mood));
    }
  }
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
    );

    assistant = Assistant(
      controller: controller,
      profile: widget.profile,
      finder: finder,
      similar: DeezerSimilarArtists(),
      media: android,
      settings: widget.settings,
      errors: widget.errors,
      weather: WeatherService(),
    );
    assistant.knowledge = MusicKnowledge();
    // Hogar inteligente: avisa a tus servicios (Home Assistant, IFTTT…) si lo configuras.
    assistant.home = HomeLink(settings: widget.settings);
    // Ecualizador inteligente y transiciones al final de cada canción (Android).
    assistant.eq = EqController(assistant: assistant, settings: widget.settings, media: android);
    if (Platform.isAndroid && android != null) {
      transitions = TransitionWatcher(settings: widget.settings, fader: _MediaFader(android!));
    }
    // Automatizaciones y comandos personalizados: los ejecuta el mismo asistente.
    automations = AutomationEngine(assistant: assistant, settings: widget.settings);
    assistant.automations = automations;
    widget.profile.isBlocked = widget.settings.isBlocked;
    widget.profile.isPrivate = () => widget.settings.privateMode;

    // Cada cambio del reproductor: perfil, asistente (radio, anuncios…) y
    // modo de escucha (abierta si no suena nada).
    controller.onActivePlayer = (status) {
      widget.profile.observe(status);
      assistant.onPlayerUpdate(status);
      unawaited(transitions?.update(status) ?? Future.value());
      _notifyHome(status);
      unawaited(voice?.setFreeMode(!(status?.isPlaying ?? false)) ?? Future.value());
    };

    if (Platform.isAndroid || Platform.isIOS) {
      final v = VoiceEngine(
        onCommand: assistant.handleCommand,
        onSearch: assistant.handleSearch,
        onIntent: assistant.handleIntent,
      )
        ..feedbackEnabled = widget.settings.voiceFeedback
        ..followHeadphones = widget.settings.followHeadphones
        ..requireWakeWord = widget.settings.wakeWord
        ..onHeadphonesChanged = ((c) => unawaited(assistant.onHeadphonesChanged(c)))
        ..attach(); // estado de audífonos desde el inicio
      unawaited(v.setCustomWake(widget.settings.wakePhrase));
      v.addListener(() {
        final e = v.error;
        if (e != null) unawaited(widget.errors?.report('voz', e) ?? Future.value());
      });
      v.guard
        ..voiceprint = widget.settings.voiceprint
        ..enabled = widget.settings.onlyMyVoice
        ..threshold = widget.settings.voiceThreshold;
      v.customIntent = automations.match;
      voice = v;
      assistant.voice = v;
      // Respuestas cortas: por ajuste o porque queda poca batería.
      void syncShort() {
        v.shortReplies = widget.settings.shortReplies || assistant.lowBattery;
        v.speechRate = widget.settings.speechRate;
        v.speechPitch = widget.settings.speechPitch;
        v.replyStyle = ReplyStyle.values.firstWhere((s) => s.name == widget.settings.replyStyle,
            orElse: () => ReplyStyle.normal);
      }
      syncShort();
      widget.settings.addListener(syncShort);
      assistant.addListener(syncShort);
      unawaited(android?.setPauseOnUnplug(widget.settings.pauseOnUnplug));
      if (Platform.isAndroid) unawaited(android?.setCallPause(widget.settings.pauseOnCalls));
      assistant.startBackground();
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
      var action = call.arguments as String?;
      // Enlaces smartbuds://… (Atajos de iPhone, Tasker, NFC…).
      if (action != null && action.startsWith('url:')) {
        action = AutomationEngine.actionForLink(action.substring(4));
      }
      if (action != null && action.startsWith('run:')) {
        await automations.runById(action.substring(4));
        return;
      }
      switch (action) {
        case 'listen':
          if (voice?.enabled == false) await voice?.start();
        case 'next':
          await assistant.handleCommand(MusicCommand.next);
        case 'favorite':
          await assistant.playFavorite();
        case 'discover':
          await assistant.discover();
        case 'like':
          await assistant.handleIntent(const LikeIntent());
      }
    });
    unawaited(channel.invokeMethod('ready').catchError((_) => null));
  }

  @override
  void dispose() {
    transitions?.dispose();
    assistant.eq?.dispose();
    automations.dispose();
    voice?.dispose();
    assistant.dispose();
    controller.dispose();
    widget.profile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.settings, builder: (context, _) => _app());
  }

  Widget _app() {
    // Apariencia elegida en Ajustes (claro/oscuro y color principal).
    final seed = Color(widget.settings.seedColor);
    return MaterialApp(
      title: 'SmartBuds AI',
      debugShowCheckedModeBanner: false,
      themeMode: switch (widget.settings.themeMode) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      theme: smartBudsTheme(Brightness.light, seed),
      darkTheme: smartBudsTheme(Brightness.dark, seed),
      // Fondo espacial animado detrás de todas las pantallas.
      builder: (context, child) => SpaceBackground(child: child ?? const SizedBox()),
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

/// Baja y sube el volumen con el lado nativo (para las transiciones).
class _MediaFader implements VolumeFader {
  _MediaFader(this.media);
  final AndroidMediaSource media;

  @override
  Future<int?> volumePercent() => media.volumePercent();

  @override
  Future<void> fadeVolume(int to, {int ms = 2000}) => media.fadeVolume(to, ms: ms);
}
