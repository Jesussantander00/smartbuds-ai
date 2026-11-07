/// Modelos compartidos por todo SmartBuds AutoConnect.
library;

/// Comandos universales. «Cambia» siempre es [MusicCommand.next],
/// sin importar qué reproductor lo reciba.
enum MusicCommand {
  play,
  pause,
  togglePlayPause,
  next,
  previous,
  volumeUp,
  volumeDown;

  bool get isVolume => this == volumeUp || this == volumeDown;

  /// Nombre que entiende el canal nativo.
  String get wireName => name;
}

/// De dónde viene la orden. Las políticas pueden tratar distinto
/// un comando de voz y un toque en la pantalla.
enum CommandSource { voice, manual }

enum PlaybackState { playing, paused, stopped, buffering, unknown }

/// Los tres niveles de control definidos en la arquitectura.
enum ControlLevel {
  /// Puede ejecutar el comando mediante una integración autorizada.
  direct,

  /// Puede consultar información, pero no ejecutar todas las acciones.
  limited,

  /// Informa al usuario y no simula resultados.
  unsupported,
}

/// Estado de un reproductor tal como lo informa su conector.
class PlayerStatus {
  const PlayerStatus({
    required this.playerId,
    required this.packageName,
    required this.appName,
    required this.state,
    this.title,
    this.artist,
    this.positionMs,
    this.lastActiveAt,
  });

  /// Identificador estable mientras dure la sesión multimedia.
  final String playerId;
  final String packageName;
  final String appName;
  final PlaybackState state;
  final String? title;
  final String? artist;
  final int? positionMs;

  /// Última vez que la sesión cambió de estado o de posición.
  final DateTime? lastActiveAt;

  bool get isPlaying => state == PlaybackState.playing;

  /// Huella de la pista actual, usada para verificar «Cambia» y «Devuelve».
  String get trackKey => '${title ?? ''}|${artist ?? ''}';

  factory PlayerStatus.fromMap(Map<dynamic, dynamic> map) {
    final lastActive = map['lastActiveAtMs'] as int?;
    return PlayerStatus(
      playerId: map['playerId'] as String,
      packageName: map['packageName'] as String,
      appName: (map['appName'] as String?) ?? map['packageName'] as String,
      state: _parseState(map['state'] as String?),
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      positionMs: map['positionMs'] as int?,
      lastActiveAt: (lastActive == null || lastActive <= 0)
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastActive),
    );
  }

  static PlaybackState _parseState(String? raw) => PlaybackState.values
      .firstWhere((s) => s.name == raw, orElse: () => PlaybackState.unknown);

  @override
  String toString() => 'PlayerStatus($appName, ${state.name}, $trackKey)';
}

/// Lo que un conector puede hacer realmente.
class Capabilities {
  const Capabilities({
    required this.supported,
    required this.level,
    this.reason,
  });

  const Capabilities.none(String this.reason)
      : supported = const {},
        level = ControlLevel.unsupported;

  final Set<MusicCommand> supported;
  final ControlLevel level;

  /// Explicación para el usuario cuando el control no es directo.
  final String? reason;

  bool allows(MusicCommand command) => supported.contains(command);

  factory Capabilities.fromCommands(Set<MusicCommand> commands) {
    final transport = commands.where((c) => !c.isVolume).toSet();
    final ControlLevel level;
    if (transport.isEmpty) {
      level = ControlLevel.limited;
    } else {
      level = ControlLevel.direct;
    }
    return Capabilities(supported: commands, level: level);
  }

  factory Capabilities.fromWire(List<dynamic> names) {
    final commands = <MusicCommand>{};
    for (final n in names) {
      for (final c in MusicCommand.values) {
        if (c.wireName == n) commands.add(c);
      }
    }
    return Capabilities.fromCommands(commands);
  }
}

enum CommandOutcome {
  /// Se envió y el Playback Verifier confirmó el cambio.
  verified,

  /// Se envió, pero el reproductor no confirmó el cambio a tiempo.
  sentUnverified,

  /// No hay reproductor activo.
  noPlayer,

  /// Hay varios candidatos y hay que preguntar al usuario.
  needsChoice,

  /// El conector o una política no permiten la acción.
  notAllowed,

  /// Falta un permiso del sistema (p. ej. acceso a notificaciones).
  permissionMissing,

  /// Error al enviar el comando.
  failed,
}

class CommandResult {
  const CommandResult(this.outcome, this.message, {this.player});

  final CommandOutcome outcome;
  final String message;
  final PlayerStatus? player;

  bool get executed =>
      outcome == CommandOutcome.verified ||
      outcome == CommandOutcome.sentUnverified;

  @override
  String toString() => 'CommandResult(${outcome.name}: $message)';
}
