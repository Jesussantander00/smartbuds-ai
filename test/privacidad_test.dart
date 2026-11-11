import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;
  var private = false;

  setUp(() {
    now = DateTime(2026, 6, 1, 10);
    private = false;
    profile = MusicProfile(clock: () => now)..isPrivate = () => private;
  });

  void listen(String title) {
    profile.observe(PlayerStatus(
      playerId: 'yt',
      packageName: 'yt',
      appName: 'YouTube',
      state: PlaybackState.playing,
      title: title,
      artist: 'A',
    ));
    now = now.add(const Duration(minutes: 4));
  }

  test('modo privado: no aprende nada', () {
    private = true;
    listen('Secreta');
    listen('Otra');
    expect(profile.tracks, isEmpty);
    expect(profile.history, isEmpty);
    private = false;
    listen('Normal');
    expect(profile.tracks.length, 1);
  });

  test('borrar un periodo', () {
    listen('Vieja');
    listen('Vieja2');
    now = now.add(const Duration(days: 3));
    listen('Nueva');
    listen('Nueva2');
    final n = profile.deleteRange(now.subtract(const Duration(hours: 1)), now);
    expect(n, greaterThan(0));
    expect(profile.tracks.keys.any((k) => k.startsWith('nueva')), isFalse);
    expect(profile.tracks.keys.any((k) => k.startsWith('vieja')), isTrue);
  });

  test('exportar historial en tabla', () {
    listen('Tusa "remix"');
    listen('Otra');
    final csv = profile.exportCsv();
    final lines = csv.split('\n');
    expect(lines.first, 'fecha,cancion,artista,evento');
    expect(csv, contains('"Tusa ""remix"""'));
    expect(csv, contains('reproducida'));
  });

  test('voz: modo privado', () {
    const p = CommandParser();
    expect((p.parseIntent('modo privado') as PrivateModeIntent).on, isTrue);
    expect((p.parseIntent('sal del modo privado') as PrivateModeIntent).on, isFalse);
  });
}
