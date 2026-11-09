import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  const p = CommandParser();

  group('Búsqueda inteligente', () {
    test('por época', () {
      expect(CommandParser.refineQuery('música de los ochenta'), 'exitos de los 80');
      expect(CommandParser.refineQuery('salsa de los noventa'), 'salsa de los 90 exitos');
      expect(p.parseSearch('busca música de los dos mil')!.query, 'exitos de los 2000');
    });

    test('versiones', () {
      expect(CommandParser.refineQuery('versión acústica de Tusa'), 'tusa acustico');
      expect(CommandParser.refineQuery('la versión en vivo de Ojalá'), 'ojala en vivo');
      expect(CommandParser.refineQuery('remix de Provenza'), 'provenza remix');
    });

    test('por descripción', () {
      expect(CommandParser.refineQuery('una canción tranquila con guitarra y voz femenina'),
          'cancion tranquila guitarra voz femenina');
      // Un título normal no se toca.
      expect(CommandParser.refineQuery('De música ligera'), 'De música ligera');
      expect(CommandParser.refineQuery('Ojalá'), 'Ojalá');
    });

    test('listas por duración', () {
      expect((p.parseIntent('pon media hora de música') as DurationIntent).minutes, 30);
      expect((p.parseIntent('pon una hora de música') as DurationIntent).minutes, 60);
      expect((p.parseIntent('pon veinte minutos de música') as DurationIntent).minutes, 20);
    });
  });

  group('Organización', () {
    late DateTime now;
    late MusicProfile profile;
    setUp(() {
      now = DateTime(2026, 6, 1, 10);
      profile = MusicProfile(clock: () => now);
    });
    void listen(String title, String artist) {
      profile.observe(PlayerStatus(
        playerId: 'yt',
        packageName: 'yt',
        appName: 'YouTube',
        state: PlaybackState.playing,
        title: title,
        artist: artist,
      ));
      now = now.add(const Duration(minutes: 4));
    }

    test('título limpio', () {
      expect(MusicProfile.cleanTitle('TUSA (Official Video)'), 'tusa');
      expect(MusicProfile.cleanTitle('Tusa ft. Nicki Minaj'), 'tusa');
      expect(MusicProfile.cleanTitle('Tusa - Letra'), 'tusa');
    });

    test('une duplicados', () {
      listen('Tusa', 'Karol G');
      listen('TUSA (Official Video)', 'Karol G');
      listen('Otra', 'X');
      expect(profile.duplicateGroups().length, 1);
      expect(profile.mergeDuplicates(), 1);
      expect(profile.duplicateGroups(), isEmpty);
      final tusa = profile.tracks.values.where((t) => MusicProfile.cleanTitle(t.title) == 'tusa');
      expect(tusa.length, 1);
      expect(tusa.first.plays, 2);
    });

    test('actuales y clásicos', () {
      listen('Vieja', 'A');
      listen('Nueva0', 'B');
      now = now.add(const Duration(days: 60));
      listen('Nueva', 'B');
      listen('Fin', 'C');
      expect(profile.currentFavorites().map((t) => t.title), contains('Nueva'));
      expect(profile.classics().map((t) => t.title), contains('Vieja'));
    });

    test('lista por duración', () {
      for (var i = 0; i < 20; i++) {
        listen('S$i', 'A');
      }
      expect(profile.playlistFor(30).length, closeTo(9, 1));
    });
  });
}
