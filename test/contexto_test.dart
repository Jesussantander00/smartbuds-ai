import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  test('rutina: hora habitual de empezar', () {
    var now = DateTime(2026, 6, 1, 7, 5); // lunes
    final profile = MusicProfile(clock: () => now);
    for (var day = 0; day < 4; day++) {
      now = DateTime(2026, 6, 1 + day, 7, 5);
      for (var i = 0; i < 3; i++) {
        profile.observe(PlayerStatus(
          playerId: 'yt',
          packageName: 'yt',
          appName: 'YouTube',
          state: PlaybackState.playing,
          title: 'S$day$i',
          artist: 'A',
        ));
        now = now.add(const Duration(minutes: 4));
      }
    }
    final p = profile.pattern();
    expect(p.sessions, 4);
    expect(p.weekdayStart, 7);
    now = DateTime(2026, 6, 8, 7, 30);
    expect(profile.isUsualListeningTime(), isTrue);
    expect(ListeningPattern.hour(19), '7 p. m.');
  });

  test('perfiles de uso', () {
    final s = AppSettings();
    s.applyUsageProfile('estudio');
    expect(s.shortReplies, isTrue);
    expect(s.announceSongs, isFalse);
    expect(s.usageProfile, 'estudio');
    s.applyUsageProfile('viaje');
    expect(s.announceSongs, isTrue);
    expect(s.radioMode, isTrue);
  });

  test('voz: perfiles y energía', () {
    const p = CommandParser();
    expect((p.parseIntent('modo estudio') as UsageProfileIntent).profile, 'estudio');
    expect(p.parseIntent('sube la energía poco a poco'), isA<EnergyRampIntent>());
    for (final phrase in AppSettings.defaultQuickCommands) {
      expect(p.parseIntent(phrase), isNotNull, reason: phrase);
    }
  });
}
