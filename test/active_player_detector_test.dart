import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';

import 'fakes.dart';

void main() {
  late InMemoryLastUsedStore lastUsed;
  late ActivePlayerDetector detector;

  setUp(() {
    lastUsed = InMemoryLastUsedStore();
    detector = ActivePlayerDetector(lastUsed: lastUsed, clock: () => t0);
  });

  PlayerCandidate c(PlayerStatus s) => FakeConnector(s).candidate;

  test('sin reproductores → NoPlayer', () {
    expect(detector.detect([]), isA<NoPlayer>());
  });

  test('1. gana el que reproduce, aunque otro esté primero', () {
    // Ejemplo del documento: Spotify pausado y YouTube Music reproduciendo.
    final r = detector.detect([
      c(status('Spotify', lastActive: t0)),
      c(status('YouTube Music', state: PlaybackState.playing)),
    ]);
    expect(r, isA<PlayerDetected>());
    final d = r as PlayerDetected;
    expect(d.candidate.status.appName, 'YouTube Music');
    expect(d.reason, DetectionReason.playing);
  });

  test('1. varios reproduciendo → el más reciente', () {
    final r = detector.detect([
      c(status('A', state: PlaybackState.playing,
          lastActive: t0.subtract(const Duration(minutes: 3)))),
      c(status('B', state: PlaybackState.playing, lastActive: t0)),
    ]) as PlayerDetected;
    expect(r.candidate.status.appName, 'B');
  });

  test('1. varios reproduciendo → gana el que muestra una canción', () {
    // Un video sin título (más reciente) no debe quitarle las órdenes a la música.
    final r = detector.detect([
      c(status('Chrome', state: PlaybackState.playing, title: '', lastActive: t0)),
      c(status('YouTube Music', state: PlaybackState.playing,
          lastActive: t0.subtract(const Duration(minutes: 1)))),
    ]) as PlayerDetected;
    expect(r.candidate.status.appName, 'YouTube Music');
  });

  test('1. empate → respeta el orden del sistema', () {
    final r = detector.detect([
      c(status('A', state: PlaybackState.playing)),
      c(status('B', state: PlaybackState.playing)),
    ]) as PlayerDetected;
    expect(r.candidate.status.appName, 'A');
  });

  test('2. recién activo gana a uno pausado hace mucho', () {
    final r = detector.detect([
      c(status('Viejo', lastActive: t0.subtract(const Duration(hours: 1)))),
      c(status('Reciente', lastActive: t0.subtract(const Duration(minutes: 1)))),
    ]) as PlayerDetected;
    expect(r.candidate.status.appName, 'Reciente');
    expect(r.reason, DetectionReason.recentlyActive);
  });

  test('2. dos recientes casi a la vez → pide elegir', () {
    final r = detector.detect([
      c(status('A', lastActive: t0.subtract(const Duration(seconds: 30)))),
      c(status('B', lastActive: t0.subtract(const Duration(seconds: 25)))),
    ]);
    expect(r, isA<NeedsChoice>());
    expect((r as NeedsChoice).candidates.length, 2);
  });

  test('3. sin actividad reciente → último utilizado', () {
    lastUsed.lastUsedPlayerId = 'B';
    final r = detector.detect([
      c(status('A')),
      c(status('B')),
    ]) as PlayerDetected;
    expect(r.candidate.status.appName, 'B');
    expect(r.reason, DetectionReason.lastUsed);
  });

  test('4. varios sin pistas → pide elegir', () {
    expect(detector.detect([c(status('A')), c(status('B'))]),
        isA<NeedsChoice>());
  });

  test('único reproductor pausado → se usa sin preguntar', () {
    final r = detector.detect([c(status('A'))]) as PlayerDetected;
    expect(r.reason, DetectionReason.onlyCandidate);
  });
}
