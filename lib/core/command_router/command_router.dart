import '../../connectors/connector_interface.dart';
import '../../connectors/youtube/youtube_search.dart';
import '../capability_manager/capability_manager.dart';
import '../connector_manager.dart';
import '../models.dart';
import '../player_detector/active_player_detector.dart';
import 'playback_verifier.dart';

/// Recibe un comando universal y lo lleva al reproductor correcto:
/// detectar → comprobar capacidades → ejecutar → verificar.
/// Nunca envía una orden a todos los reproductores a la vez.
class CommandRouter {
  CommandRouter({
    required this.connectors,
    required this.detector,
    required this.capabilities,
    required this.lastUsed,
    this.volume,
    this.search,
    this.songFinder,
    this.verifier = const PlaybackVerifier(),
  });

  /// Encuentra la canción exacta en YouTube (requiere clave). Con ella,
  /// YouTube Music reproduce directo en vez de mostrar resultados.
  final SongFinder? songFinder;

  /// App por defecto para buscar cuando no hay ningún reproductor activo.
  static const defaultSearchPackage = 'com.google.android.apps.youtube.music';

  final ConnectorManager connectors;
  final ActivePlayerDetector detector;
  final CapabilityManager capabilities;
  final LastUsedStore lastUsed;
  final SystemVolumeController? volume;
  final SearchPlayer? search;
  final PlaybackVerifier verifier;

  /// Último resultado de detección (útil para la UI cuando hay que elegir).
  DetectionResult? lastDetection;

  Future<CommandResult> route(
    MusicCommand command, {
    CommandSource source = CommandSource.voice,
  }) async {
    if (command.isVolume) return _routeVolume(command);

    final missing = await connectors.missingPermissions();
    final candidates = await connectors.candidates();
    if (candidates.isEmpty && missing.isNotEmpty) {
      return CommandResult(
        CommandOutcome.permissionMissing,
        missing.values.first,
      );
    }

    final detection = detector.detect(candidates);
    lastDetection = detection;
    switch (detection) {
      case NoPlayer():
        return const CommandResult(
          CommandOutcome.noPlayer,
          'No hay ningún reproductor activo.',
        );
      case NeedsChoice(candidates: final options):
        final names = options.map((c) => c.status.appName).join(', ');
        return CommandResult(
          CommandOutcome.needsChoice,
          '¿Qué reproductor quieres controlar? $names',
        );
      case PlayerDetected(:final candidate):
        return executeOn(candidate, command, source: source);
    }
  }

  /// Ejecuta sobre un reproductor concreto (p. ej. el que eligió el usuario).
  Future<CommandResult> executeOn(
    PlayerCandidate candidate,
    MusicCommand command, {
    required CommandSource source,
  }) async {
    final connector = candidate.connector;
    final before = candidate.status;

    final caps = await capabilities.evaluate(connector, before, source);
    if (!caps.allows(command)) {
      return CommandResult(
        CommandOutcome.notAllowed,
        caps.reason ??
            '${before.appName} no permite «${command.name}» desde SmartBuds.',
        player: before,
      );
    }

    final CommandResult sent;
    try {
      sent = await connector.execute(command);
    } catch (e) {
      return CommandResult(CommandOutcome.failed, 'Error al enviar: $e',
          player: before);
    }
    if (!sent.executed) return sent;

    lastUsed.lastUsedPlayerId = before.playerId;

    final ok = await verifier.verify(connector, command, before);
    return ok
        ? CommandResult(CommandOutcome.verified,
            '${before.appName}: ${command.name} confirmado.',
            player: before)
        : CommandResult(CommandOutcome.sentUnverified,
            '${before.appName}: orden enviada, sin confirmación del reproductor.',
            player: before);
  }

  /// «busca <query>»: busca y reproduce en el reproductor activo
  /// (o en YouTube Music si no hay ninguno), respetando las políticas.
  Future<CommandResult> routeSearch(
    String query, {
    String? appPackage,
    String? appName,
    CommandSource source = CommandSource.voice,
  }) async {
    final s = search;
    if (s == null) {
      return const CommandResult(CommandOutcome.notAllowed,
          'La búsqueda no está disponible en este dispositivo.');
    }
    final candidates = await connectors.candidates();
    final detection = detector.detect(candidates);
    final active = detection is PlayerDetected ? detection.candidate.status : null;

    // Destino: la app pedida («en Apple Music»), si no la activa,
    // si no la última usada, y si no YouTube Music.
    PlayerStatus? player;
    String pkg;
    if (appPackage != null) {
      pkg = appPackage;
      player = candidates
          .map((c) => c.status)
          .where((st) => st.packageName == appPackage)
          .firstOrNull;
    } else if (active != null) {
      pkg = active.packageName;
      player = active;
    } else {
      pkg = lastSearchPackage ?? defaultSearchPackage;
    }
    final targetName = player?.appName ?? appName ??
        (pkg == defaultSearchPackage ? 'YouTube Music' : pkg);

    final policy = capabilities.policyFor(pkg);
    if (policy != null && policy.blockedSources.contains(source)) {
      return CommandResult(CommandOutcome.notAllowed, policy.reason, player: player);
    }
    final before = player?.trackKey;

    // 0) YouTube Music + clave de YouTube: enlace directo a la canción exacta,
    //    que YouTube Music reproduce de inmediato (luego sigue con relacionadas).
    final finder = songFinder;
    if (pkg == defaultSearchPackage && finder != null) {
      final hit = await finder.find(query);
      if (hit != null) {
        final link = 'https://music.youtube.com/watch?v=${hit.videoId}';

        // 0a) Invisible: por la sesión multimedia, sin abrir YouTube Music.
        if (player != null) {
          final sent = await s.playUriInSession(
              packageName: pkg, uri: link, mediaId: hit.videoId);
          if (sent && await _trackChanged(pkg, before, searchSessionWait)) {
            lastSearchPackage = pkg;
            return CommandResult(CommandOutcome.verified,
                'Reproduciendo «${hit.title}» en $targetName.',
                player: player);
          }
        }

        // 0b) Respaldo: enlace directo (YouTube Music se ve un instante).
        final opened = await s.openUri(uri: link, packageName: pkg);
        if (opened) {
          lastSearchPackage = pkg;
          if (await _trackChanged(pkg, before, searchIntentWait)) {
            await s.returnToApp();
            return CommandResult(CommandOutcome.verified,
                'Reproduciendo «${hit.title}» en $targetName.',
                player: player);
          }
          await s.returnToApp();
          return CommandResult(CommandOutcome.sentUnverified,
              'Abrí «${hit.title}» en $targetName, pero no confirmó que esté sonando.',
              player: player);
        }
      }
    }

    // 1) Directo a la sesión multimedia, si la app tiene una activa.
    if (player != null) {
      final sent = await s.playFromSearch(
          packageName: pkg, query: query, mode: SearchMode.session);
      if (sent && await _trackChanged(pkg, before, searchSessionWait)) {
        lastSearchPackage = pkg;
        return CommandResult(CommandOutcome.verified,
            'Reproduciendo «$query» en $targetName.',
            player: player);
      }
    }

    // 2) Intención de búsqueda estándar.
    final ok = await s.playFromSearch(
        packageName: pkg, query: query, mode: SearchMode.intent);
    if (!ok) {
      return CommandResult(CommandOutcome.failed,
          '$targetName no aceptó la búsqueda de «$query». ¿Está instalada?',
          player: player);
    }
    lastSearchPackage = pkg;
    if (await _trackChanged(pkg, before, searchIntentWait)) {
      // La canción ya suena: SmartBuds vuelve al frente y la música sigue de fondo.
      await s.returnToApp();
      return CommandResult(CommandOutcome.verified,
          'Reproduciendo «$query» en $targetName.',
          player: player);
    }
    return CommandResult(CommandOutcome.sentUnverified,
        '$targetName abrió la búsqueda de «$query», pero no empezó a reproducirla.',
        player: player);
  }

  /// Última app donde se buscó (destino por defecto de la siguiente búsqueda).
  String? lastSearchPackage;

  /// Cuánto esperar a que cambie la canción tras cada intento de búsqueda.
  Duration searchSessionWait = const Duration(seconds: 3);
  Duration searchIntentWait = const Duration(seconds: 5);

  /// ¿La app [pkg] está sonando una pista distinta de [before]?
  Future<bool> _trackChanged(String pkg, String? before, Duration wait) async {
    final deadline = DateTime.now().add(wait);
    while (true) {
      for (final c in await connectors.candidates()) {
        final st = c.status;
        if (st.packageName == pkg &&
            st.title != null &&
            st.trackKey != before &&
            (st.isPlaying || st.state == PlaybackState.buffering)) {
          return true;
        }
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<CommandResult> _routeVolume(MusicCommand command) async {
    final v = volume;
    if (v == null) {
      return const CommandResult(CommandOutcome.notAllowed,
          'El control de volumen no está disponible en este dispositivo.');
    }
    final ok = await v.adjust(up: command == MusicCommand.volumeUp);
    return ok
        ? const CommandResult(CommandOutcome.verified, 'Volumen ajustado.')
        : const CommandResult(
            CommandOutcome.failed, 'No se pudo ajustar el volumen.');
  }
}
