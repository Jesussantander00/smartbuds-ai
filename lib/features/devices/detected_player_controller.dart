import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/capability_manager/capability_manager.dart';
import '../../core/command_router/command_router.dart';
import '../../core/connector_manager.dart';
import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';

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
    notifyListeners();
  }

  void setTestSource(CommandSource s) {
    testSource = s;
    notifyListeners();
  }

  Future<void> send(MusicCommand command) => _run(
      () => router.route(command, source: testSource));

  Future<void> sendTo(PlayerCandidate c, MusicCommand command) => _run(
      () => router.executeOn(c, command, source: testSource));

  Future<void> _run(Future<CommandResult> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      lastResult = await action();
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
