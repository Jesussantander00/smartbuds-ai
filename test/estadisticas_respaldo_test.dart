import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/features/backup/backup_service.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';
import 'package:smartbuds_ai/features/stats/advanced_stats.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;

  setUp(() {
    now = DateTime(2026, 11, 9, 20); // lunes 8 p. m.
    profile = MusicProfile(clock: () => now);
  });

  void listen(String title, String artist, {int minutes = 4}) {
    profile.observe(PlayerStatus(
      playerId: 'sp',
      packageName: 'sp',
      appName: 'Spotify',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    ));
    now = now.add(Duration(minutes: minutes));
  }

  group('Estadísticas avanzadas', () {
    test('artistas por tiempo, hora favorita y mapa de calor', () {
      for (var i = 0; i < 3; i++) {
        listen('A$i', 'Feid', minutes: 5);
      }
      listen('B', 'Karol G', minutes: 3);
      listen('C', 'Feid');
      final s = AdvancedStats.from(profile, now: now);
      expect(s.artists.first.name, 'Feid');
      expect(s.artists.first.listened, greaterThanOrEqualTo(const Duration(minutes: 15)));
      expect(s.artists.first.songs, 4);
      expect(s.peakHour, 20);
      expect(s.heat[0][20], greaterThan(0)); // lunes 20 h
      expect(s.topShare, greaterThan(50));
    });

    test('rachas de días seguidos', () {
      for (var d = 0; d < 3; d++) {
        listen('Día $d', 'X');
        now = now.add(const Duration(days: 1));
      }
      final s = AdvancedStats.from(profile, now: now.subtract(const Duration(days: 1)));
      expect(s.currentStreak, 3);
      expect(s.bestStreak, 3);
      expect(s.activeDays, 3);
    });

    test('descubrimientos del mes y los que se quedaron', () {
      for (var i = 0; i < 3; i++) {
        listen('N$i', 'Nuevo');
      }
      listen('U', 'Una vez');
      final s = AdvancedStats.from(profile, now: now);
      expect(s.discoveries.map((a) => a.name), containsAll(['Nuevo', 'Una vez']));
      expect(s.keepers.map((a) => a.name), ['Nuevo']);
      expect(s.discoveryRate, 50);
    });
  });

  group('Copia de seguridad', () {
    test('no incluye la sesión ni la huella de voz', () {
      final settings = AppSettings()
        ..authUserId = 'u1'
        ..authRefreshToken = 'secreto'
        ..voiceprint = [1, 2, 3];
      final data = BackupService(settings: settings, profile: profile).build(device: 'Mi tel');
      final text = jsonEncode(data);
      expect(text, isNot(contains('secreto')));
      expect((data['prefs'] as Map).containsKey('authUserId'), isFalse);
      expect((data['prefs'] as Map).containsKey('voiceprint'), isFalse);
      expect((data['prefs'] as Map).containsKey('deviceId'), isFalse);
    });

    test('restaura ajustes, automatizaciones y gustos en otro teléfono', () async {
      final a = AppSettings()
        ..setCarDevice('Mazda', true)
        ..setVolumeCap('Buds', 70)
        ..setAutomations([
          {'id': 'aaaaaaaa', 'name': 'Gym', 'kind': 'phrase', 'phrase': 'vamos al gym', 'steps': ['volumen al 80']},
        ]);
      listen('Ojalá', 'Ryan Castro');
      listen('Otra', 'Feid');
      final text = BackupService(settings: a, profile: profile).exportText(device: 'Viejo');

      final b = AppSettings()..authUserId = 'nuevo';
      final p2 = MusicProfile();
      final r = await BackupService(settings: b, profile: p2).restore(text);
      expect(r, isNotNull);
      expect(r!.automations, 1);
      expect(r.songs, greaterThanOrEqualTo(2));
      expect(b.carDevices, contains('Mazda'));
      expect(b.volumeCaps['Buds'], 70);
      expect(b.authUserId, 'nuevo'); // la sesión de este teléfono se conserva
      expect(p2.tracks.length, greaterThanOrEqualTo(2));
    });

    test('rechaza lo que no es una copia y acepta las copias viejas de gustos', () async {
      final s = BackupService(settings: AppSettings(), profile: MusicProfile());
      expect(await s.restore('hola'), isNull);
      expect(await s.restore('{"app":"otra"}'), isNull);
      listen('Vieja', 'Artista');
      final old = profile.exportJson();
      final r = await s.restore(old);
      expect(r?.songs, 1);
    });
  });
}
