import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/command_router/playback_verifier.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';

import 'fakes.dart';

void main() {
  late InMemoryLastUsedStore lastUsed;

  CommandRouter routerFor(FakeSource source) {
    lastUsed = InMemoryLastUsedStore();
    return CommandRouter(
      connectors: ConnectorManager([source]),
      detector: ActivePlayerDetector(lastUsed: lastUsed, clock: () => t0),
      capabilities: CapabilityManager(),
      lastUsed: lastUsed,
      verifier: const PlaybackVerifier(
        timeout: Duration(milliseconds: 100),
        interval: Duration(milliseconds: 10),
      ),
    );
  }

  test('«Cambia» va solo al reproductor activo y se verifica', () async {
    final paused = FakeConnector(status('Spotify', pkg: 'com.spotify.music'));
    final playing = FakeConnector(status('YT', state: PlaybackState.playing));
    final router = routerFor(FakeSource([paused, playing]));

    final r = await router.route(MusicCommand.next);

    expect(r.outcome, CommandOutcome.verified);
    expect(playing.received, [MusicCommand.next]);
    expect(paused.received, isEmpty, reason: 'nunca enviar a todos');
    expect(lastUsed.lastUsedPlayerId, 'YT');
  });

  test('«Pausa» confirmada por el verificador', () async {
    final p = FakeConnector(status('A', state: PlaybackState.playing));
    final r = await routerFor(FakeSource([p])).route(MusicCommand.pause);
    expect(r.outcome, CommandOutcome.verified);
    expect(p.current.state, PlaybackState.paused);
  });

  test('reproductor que ignora la orden → sentUnverified, no éxito falso',
      () async {
    final p = FakeConnector(status('A', state: PlaybackState.playing),
        obeys: false);
    final r = await routerFor(FakeSource([p])).route(MusicCommand.next);
    expect(r.outcome, CommandOutcome.sentUnverified);
  });

  test('Spotify por voz: bloqueado y sin enviar nada', () async {
    final s = FakeConnector(status('Spotify',
        pkg: 'com.spotify.music', state: PlaybackState.playing));
    final r = await routerFor(FakeSource([s])).route(MusicCommand.next);
    expect(r.outcome, CommandOutcome.notAllowed);
    expect(s.received, isEmpty);
  });

  test('acción no declarada por el conector → notAllowed', () async {
    final p = FakeConnector(status('Radio', state: PlaybackState.playing),
        supported: {MusicCommand.play, MusicCommand.pause});
    final r = await routerFor(FakeSource([p])).route(MusicCommand.next);
    expect(r.outcome, CommandOutcome.notAllowed);
    expect(p.received, isEmpty);
  });

  test('sin permiso → permissionMissing', () async {
    final r = await routerFor(FakeSource([], permissionMessage: 'Falta acceso'))
        .route(MusicCommand.pause);
    expect(r.outcome, CommandOutcome.permissionMissing);
  });

  test('sin reproductores → noPlayer', () async {
    final r = await routerFor(FakeSource([])).route(MusicCommand.pause);
    expect(r.outcome, CommandOutcome.noPlayer);
  });

  test('ambiguo → needsChoice y no envía nada', () async {
    final a = FakeConnector(status('A'));
    final b = FakeConnector(status('B'));
    final r = await routerFor(FakeSource([a, b])).route(MusicCommand.play);
    expect(r.outcome, CommandOutcome.needsChoice);
    expect(a.received, isEmpty);
    expect(b.received, isEmpty);
  });

  test('volumen sin controlador → notAllowed', () async {
    final r = await routerFor(FakeSource([])).route(MusicCommand.volumeUp);
    expect(r.outcome, CommandOutcome.notAllowed);
  });
}
