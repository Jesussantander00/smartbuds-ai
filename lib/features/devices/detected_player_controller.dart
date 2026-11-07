import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/capability_manager/capability_manager.dart';
import '../../core/command_router/command_router.dart';
import '../../core/connector_manager.dart';
import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/command_parser.dart';

/// Un reproductor con sus capacidades efectivas para la pantalla.
class PlayerView {
  const PlayerView(this.candidate, this.voiceCaps, this.manualCaps);
  final PlayerCandidate candidate;
  final Capabilities voiceCaps;
  final Capabilities manualCaps;
  PlayerStatus get status => candidate.status;
}

/// Estado de la pantalla «Reproductor detectado».
class DetectedPlayerController extends ChangeNotifier {
  DetectedPlayerController({
    required this.connectors,
    required this.detector,
    required this.capabilities,
    required this.router,
  });

  final ConnectorManager connectors;
  final ActivePlayerDetector detector;
  final CapabilityManager capabilities;
  final CommandRouter router;

  StreamSubscription<void>? _sub;
  Timer? _debounce;

  Map<String, String> missingPermissions = const {};
  List<PlayerView> players = const [];
  DetectionResult detection = const NoPlayer();
  CommandResult? lastResult;
  bool busy = false;

  /// Se llama con el reproductor activo en cada actualización
  /// (lo usa el perfil musical para aprender qué escuchas).
  void Function(PlayerStatus? active)? onActivePlayer;

  /// Para probar políticas sin el motor de voz: los botones envían
  /// el comando como si viniera de la voz.
  CommandSource testSource = CommandSource.voice;

  Future<void> start() async {
    _sub = connectors.changes.listen((_) => _scheduleRefresh());
    await refresh();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> refresh() async {
    missingPermissions = await connectors.missingPermissions();
    final candidates = await connectors.candidates();
    final views = <PlayerView>[];
    for (final c in candidates) {
      final declared = await c.connector.getCapabilities();
      views.add(PlayerView(
        c,
        capabilities.applyPolicy(
            declared, c.status.packageName, CommandSource.voice),
        capabilities.applyPolicy(
            declared, c.status.packageName, CommandSource.manual),
      ));
    }
    players = views;
    detection = detector.detect(candidates);
    final d = detection;
    onActivePlayer?.call(d is PlayerDetected ? d.candidate.status : null);
    notifyListeners();
  }

  void setTestSource(CommandSource s) {
    testSource = s;
    notifyListeners();
  }

  Future<CommandResult?> send(MusicCommand command) => _run(
      () => router.route(command, source: testSource));

  /// Campo de búsqueda de pruebas: acepta lo mismo que la voz
  /// («Ojalá Ryan Castro» o «Ojalá en Apple Music»).
  Future<void> search(String text, {CommandSource? source}) async {
    if (text.trim().isEmpty) return;
    final request = const CommandParser().parseSearch('busca $text') ??
        SearchRequest(text.trim());
    await searchRequest(request, source: source ?? testSource);
  }

  Future<CommandResult?> searchRequest(SearchRequest r, {CommandSource? source}) async {
    if (busy) return null;
    return _run(() => router.routeSearch(
          r.query,
          appPackage: r.appPackage,
          appName: r.appName,
          source: source ?? testSource,
        ));
  }

  Future<CommandResult?> searchVoice(SearchRequest r) =>
      searchRequest(r, source: CommandSource.voice);

  /// Comando que llega del Voice Engine (siempre con origen voz).
  Future<CommandResult?> sendVoice(MusicCommand command) async {
    if (busy) return null;
    return _run(() => router.route(command, source: CommandSource.voice));
  }

  Future<CommandResult?> sendTo(PlayerCandidate c, MusicCommand command) => _run(
      () => router.executeOn(c, command, source: testSource));

  Future<CommandResult?> _run(Future<CommandResult> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      lastResult = await action();
      return lastResult;
    } finally {
      busy = false;
      await refresh();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
