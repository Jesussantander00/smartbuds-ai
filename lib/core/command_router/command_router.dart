import '../../connectors/connector_interface.dart';
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
    this.verifier = const PlaybackVerifier(),
  });

  final ConnectorManager connectors;
  final ActivePlayerDetector detector;
  final CapabilityManager capabilities;
  final LastUsedStore lastUsed;
  final SystemVolumeController? volume;
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
