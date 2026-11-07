import '../../connectors/connector_interface.dart';
import '../models.dart';

/// Comprueba que el reproductor hizo lo que se le pidió.
/// No inventa resultados: si no puede confirmarlo, lo dice.
class PlaybackVerifier {
  const PlaybackVerifier({
    this.timeout = const Duration(milliseconds: 2000),
    this.interval = const Duration(milliseconds: 150),
  });

  final Duration timeout;
  final Duration interval;

  Future<bool> verify(
    MusicConnector connector,
    MusicCommand command,
    PlayerStatus before,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final after = await connector.getStatus();
        if (isConfirmed(command, before, after)) return true;
      } catch (_) {
        // La sesión puede desaparecer un instante al cambiar de pista.
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(interval);
    }
  }

  /// Regla pura de confirmación por comando.
  static bool isConfirmed(
    MusicCommand command,
    PlayerStatus before,
    PlayerStatus after,
  ) {
    switch (command) {
      case MusicCommand.pause:
        return after.state != PlaybackState.playing &&
            after.state != PlaybackState.buffering;
      case MusicCommand.play:
        return after.state == PlaybackState.playing ||
            after.state == PlaybackState.buffering;
      case MusicCommand.togglePlayPause:
        return before.isPlaying != after.isPlaying;
      case MusicCommand.next:
        return _trackChanged(before, after);
      case MusicCommand.previous:
        if (_trackChanged(before, after)) return true;
        // «Devuelve» a mitad de canción suele reiniciarla en vez de cambiarla.
        final b = before.positionMs, a = after.positionMs;
        return b != null && a != null && b > 3000 && a < 3000;
      case MusicCommand.volumeUp:
      case MusicCommand.volumeDown:
        return true; // El volumen lo confirma el sistema, no el reproductor.
    }
  }

  static bool _trackChanged(PlayerStatus before, PlayerStatus after) {
    if (before.title == null && after.title == null) return false;
    return before.trackKey != after.trackKey;
  }
}
