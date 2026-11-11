import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';
import 'package:smartbuds_ai/features/social/social_service.dart';

void main() {
  test('código de amigo fácil de dictar', () {
    final code = SocialService.newFriendCode(Random(1));
    expect(code.length, 6);
    expect(RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code), isTrue);
  });

  test('compatibilidad y descubrir por amigos', () {
    var now = DateTime(2026, 6, 1, 10);
    final p = MusicProfile(clock: () => now);
    for (final a in ['Karol G', 'Feid', 'Feid', 'Bad Bunny']) {
      p.observe(PlayerStatus(
        playerId: 'yt',
        packageName: 'yt',
        appName: 'YouTube',
        state: PlaybackState.playing,
        title: 'S $a $now',
        artist: a,
      ));
      now = now.add(const Duration(minutes: 4));
    }
    final c = p.compareArtists(['Feid', 'Karol G', 'Shakira']);
    expect(c.shared, containsAll(['Feid', 'Karol G']));
    expect(c.percent, greaterThan(0));
    expect(p.newFromFriend(['Feid', 'Shakira']), ['Shakira']);
  });
}
