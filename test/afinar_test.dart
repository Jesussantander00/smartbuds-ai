import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/ui/live_visuals.dart';
import 'package:smartbuds_ai/features/brain/music_brain.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  late DateTime now;
  late MusicProfile profile;
  late MusicBrain brain;

  setUp(() {
    now = DateTime(2026, 6, 1, 9);
    profile = MusicProfile(clock: () => now);
    brain = MusicBrain(profile: profile, settings: AppSettings(), clock: () => now);
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

  void fill() {
    for (var i = 0; i < 12; i++) {
      listen('Relleno $i', 'Otro $i');
    }
  }

  test('un solo salto no descarta una canción; dos sí', () {
    listen('Ojalá', 'Ryan Castro');
    fill();
    final key = MusicProfile.keyFor('Ojalá', 'Ryan Castro');
    profile.tracks[key]!.skips = 1;
    bool has() => brain.recommend(BrainContext(now: now), n: 20).any((r) => r.track.key == key);
    expect(has(), isTrue);
    profile.tracks[key]!.skips = 2;
    expect(has(), isFalse);
  });

  test('con pocos datos reconoce que está aprendiendo', () {
    expect(brain.readiness().learning, isTrue);
    expect(brain.readiness().plays, 0);
    for (var i = 0; i < MusicBrain.minPlays; i++) {
      listen('C$i', 'A${i % 5}');
    }
    expect(brain.readiness().learning, isFalse);
  });

  test('variedad: primero artistas distintos', () {
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 6; i++) {
        listen('Feid $i', 'Feid');
      }
    }
    for (var i = 0; i < 6; i++) {
      listen('Otra $i', 'Artista $i');
    }
    fill();
    final recs = brain.recommend(BrainContext(now: now.add(const Duration(hours: 5))), n: 5);
    final artists = recs.map((r) => r.track.artist).toList();
    expect(artists.toSet().length, artists.length);
  });

  test('cada razón muestra un dato real comprobable', () {
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 6; i++) {
        listen('Canción $i', 'Artista $i');
      }
    }
    profile.likeTrack(MusicProfile.keyFor('Canción 0', 'Artista 0'));
    fill(); // lo reciente no se recomienda
    final recs = brain.recommend(BrainContext(now: now.add(const Duration(hours: 3)), sessionSkips: 2), n: 6);
    expect(recs, isNotEmpty);
    for (final r in recs) {
      for (final reason in r.reasons) {
        expect(reason == 'Le diste «me gusta»' || RegExp(r'\d').hasMatch(reason), isTrue, reason: reason);
      }
    }
  });

  test('visualizador: el silencio vuelve a la animación normal', () {
    final b = AudioBands.instance;
    b.onBands(List.filled(16, .5));
    expect(b.bands.value, isNotNull);
    for (var i = 0; i < AudioBands.silentToFallback; i++) {
      b.onBands(List.filled(16, 0));
    }
    expect(b.bands.value, isNull);
    b.onBands(List.filled(16, .4));
    expect(b.bands.value, isNotNull);
  });

  testWidgets('«reducir movimiento» apaga la carátula viva', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LiveArt(playing: true, child: SizedBox(width: 50, height: 50)),
      ),
    ));
    expect(find.descendant(of: find.byType(LiveArt), matching: find.byType(Transform)), findsNothing);
  });
}
