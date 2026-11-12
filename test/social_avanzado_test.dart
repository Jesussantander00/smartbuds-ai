import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';
import 'package:smartbuds_ai/features/social/achievements.dart';
import 'package:smartbuds_ai/features/social/social_service.dart';

void main() {
  test('la sala calcula dónde va la canción del anfitrión', () {
    final t0 = DateTime(2026, 1, 1, 10);
    final r = RoomState(id: 'r', code: 'X', isHost: false, title: 'Tusa', positionMs: 30000, playing: true, updatedAt: t0);
    expect(r.positionNow(t0.add(const Duration(seconds: 12))), 42000);
    final paused = RoomState(id: 'r', code: 'X', isHost: false, positionMs: 30000, playing: false, updatedAt: t0);
    expect(paused.positionNow(t0.add(const Duration(minutes: 5))), 30000);
  });

  test('insignias y desafíos con tu escucha', () {
    var now = DateTime(2026, 6, 3, 10); // miércoles
    final profile = MusicProfile(clock: () => now);
    final settings = AppSettings();
    for (var day = 0; day < 3; day++) {
      now = DateTime(2026, 6, 1 + day, 10);
      for (var i = 0; i < 5; i++) {
        profile.observe(PlayerStatus(
          playerId: 'yt',
          packageName: 'yt',
          appName: 'YouTube',
          state: PlaybackState.playing,
          title: 'S$day$i',
          artist: 'Artista $day$i',
        ));
        now = now.add(const Duration(minutes: 4));
      }
    }
    settings.logSocial('sent');
    final a = Achievements(profile, settings, clock: () => DateTime(2026, 6, 3, 20));
    final badges = {for (final b in a.badges(mutualFriends: 3)) b.id: b};
    expect(badges['explorer']!.earned, isTrue); // 15 artistas
    expect(badges['streak']!.progress, 3);
    expect(badges['social']!.earned, isTrue);
    expect(badges['generous']!.progress, 1);
    final weekly = a.weekly();
    expect(weekly.length, 3);
    expect(weekly.map((c) => c.title).toSet().length, 3); // sin repetir
  });
}
