import 'package:smartbuds_ai/connectors/connector_interface.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';

final t0 = DateTime(2026, 11, 7, 12, 0, 0);

PlayerStatus status(
  String id, {
  PlaybackState state = PlaybackState.paused,
  String? pkg,
  String title = 'Canción A',
  DateTime? lastActive,
  int? positionMs,
}) =>
    PlayerStatus(
      playerId: id,
      packageName: pkg ?? 'com.example.$id',
      appName: id,
      state: state,
      title: title,
      artist: 'Artista',
      lastActiveAt: lastActive,
      positionMs: positionMs,
    );

/// Reproductor simulado: obedece los comandos (o los ignora si
/// [obeys] es false) y cuenta lo que recibe.
class FakeConnector implements MusicConnector {
  FakeConnector(this.current,
      {Set<MusicCommand>? supported, this.obeys = true})
      : supported = supported ??
            {
              MusicCommand.play,
              MusicCommand.pause,
              MusicCommand.togglePlayPause,
              MusicCommand.next,
              MusicCommand.previous,
            };

  PlayerStatus current;
  final Set<MusicCommand> supported;
  final bool obeys;
  final received = <MusicCommand>[];
  int _track = 0;

  PlayerCandidate get candidate => PlayerCandidate(this, current);

  @override
  String get connectorId => 'fake';

  @override
  String get playerId => current.playerId;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlayerStatus> getStatus() async => current;

  @override
  Future<Capabilities> getCapabilities() async =>
      Capabilities.fromCommands(supported);

  @override
  Future<CommandResult> execute(MusicCommand command) async {
    received.add(command);
    if (obeys) {
      final s = current;
      PlaybackState state = s.state;
      String? title = s.title;
      if (command == MusicCommand.pause) state = PlaybackState.paused;
      if (command == MusicCommand.play) state = PlaybackState.playing;
      if (command == MusicCommand.next || command == MusicCommand.previous) {
        title = 'Pista ${++_track}';
      }
      current = PlayerStatus(
        playerId: s.playerId,
        packageName: s.packageName,
        appName: s.appName,
        state: state,
        title: title,
        artist: s.artist,
        lastActiveAt: s.lastActiveAt,
      );
    }
    return const CommandResult(CommandOutcome.sentUnverified, 'Enviado.');
  }
}

class FakeSource implements PlayerSource {
  FakeSource(this.connectors, {this.permissionMessage});
  final List<FakeConnector> connectors;
  String? permissionMessage;

  @override
  String get sourceId => 'fake';

  @override
  Future<String?> missingPermission() async => permissionMessage;

  @override
  Future<List<MusicConnector>> discover() async => connectors;

  @override
  Stream<void> get changes => const Stream.empty();
}
