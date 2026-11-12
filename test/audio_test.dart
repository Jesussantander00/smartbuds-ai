import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;

  setUp(() {
    now = DateTime(2026, 6, 1, 9);
    profile = MusicProfile(clock: () => now);
  });

  void listen(String title, String artist, {int minutes = 4}) {
    profile.observe(PlayerStatus(
      playerId: 'yt',
      packageName: 'yt',
      appName: 'YouTube',
      state: PlaybackState.playing,
      title: title,
      artist: artist,
    ));
    now = now.add(Duration(minutes: minutes));
  }

  test('separa sesiones por pausas largas y cuenta tiempo, terminadas y artistas', () {
    listen('A', 'Feid');
    listen('B', 'Feid');
    listen('C', 'Karol G');
    now = now.add(const Duration(hours: 2));
    listen('D', 'Bad Bunny');
    listen('E', 'Bad Bunny');

    final r = profile.sessionReports();
    expect(r, hasLength(2));
    // La más reciente primero.
    expect(r.first.songs, 2);
    expect(r.first.artists, 1);
    final old = r.last;
    expect(old.songs, 3);
    expect(old.artists, 2);
    expect(old.completes, 2);
    expect(old.longestStreak, 2);
    expect(old.skips, 0);
    expect(old.skipRate, 0);
    expect(old.listened, greaterThanOrEqualTo(const Duration(minutes: 8)));
  });

  test('sin historial no hay sesiones', () {
    expect(profile.sessionReports(), isEmpty);
  });

  test('límite de volumen por audífono y transición suave se guardan', () {
    final s = AppSettings();
    expect(s.smoothTransitions, isFalse);
    s.setVolumeCap('Buds', 70);
    expect(s.volumeCaps['Buds'], 70);
    s.setVolumeCap('Buds', null);
    expect(s.volumeCaps.containsKey('Buds'), isFalse);
    s.update(smoothTransitions: true);
    expect(s.smoothTransitions, isTrue);
  });
}
