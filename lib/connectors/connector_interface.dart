import '../core/models.dart';

/// Interfaz común de todos los conectores (Android Media Session,
/// Apple Music, reproductor local…). Cada instancia representa un
/// reproductor concreto y declara lo que puede hacer realmente.
abstract class MusicConnector {
  /// Identificador del conector, p. ej. `android_media`, `apple_music`.
  String get connectorId;

  /// Identificador del reproductor que controla esta instancia.
  String get playerId;

  Future<bool> isAvailable();

  Future<PlayerStatus> getStatus();

  Future<CommandResult> execute(MusicCommand command);

  Future<Capabilities> getCapabilities();
}

/// Una fuente que descubre reproductores y entrega un conector por cada uno.
/// En Android, una única fuente (MediaSessionManager) produce un conector
/// por cada sesión multimedia activa.
abstract class PlayerSource {
  String get sourceId;

  /// Si falta un permiso del sistema, devuelve una explicación; si no, null.
  Future<String?> missingPermission();

  Future<List<MusicConnector>> discover();

  /// Emite cada vez que cambian las sesiones (abrir, pausar, cambiar pista…).
  Stream<void> get changes;
}

/// El volumen pertenece al sistema, no a un reproductor concreto.
abstract class SystemVolumeController {
  Future<bool> adjust({required bool up});
}
