import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/ui/live_visuals.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';
import 'package:smartbuds_ai/features/brain/music_brain.dart';
import 'package:smartbuds_ai/features/curator/curator.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('núcleo de Jarvis: esperando, escuchando, ejecutando y respondiendo', () {
    var now = DateTime(2026, 11, 13, 22);
    final v = VoiceEngine(onCommand: (_) async {}, onIntent: (_) async {}, clock: () => now);
    expect(v.jarvisState, JarvisState.off);
    v.enabled = true;
    expect(v.jarvisState, JarvisState.waiting);
    v.handleEvent({'type': 'state', 'listening': true});
    expect(v.jarvisState, JarvisState.listening);
    v.runIntent(const LikeIntent());
    expect(v.jarvisState, JarvisState.working);
    now = now.add(const Duration(seconds: 3));
    expect(v.jarvisState, JarvisState.listening);
    v.handleEvent({'type': 'speaking', 'on': true});
    expect(v.jarvisState, JarvisState.responding);
    v.handleEvent({'type': 'speaking', 'on': false});
    expect(v.jarvisState, JarvisState.listening);
  });

  test('efectos visuales: intensidad y ritmo por ambiente', () {
    final s = AppSettings();
    expect(s.visualFactor, 1.0);
    s.update(visualIntensity: 0);
    expect(s.visualFactor, 0.0);
    s.update(visualIntensity: 9);
    expect(s.visualIntensity, 3);
    expect(songTempo('para entrenar'), 2);
    expect(songTempo('dormir'), .6);
    expect(songTempo(null), 1);
  });

  group('curador', () {
    late DateTime now;
    late MusicProfile profile;
    late AppSettings settings;
    late Curator curator;

    void listen(String title, String artist) {
      profile.observe(PlayerStatus(
        playerId: 'sp',
        packageName: 'sp',
        appName: 'Spotify',
        state: PlaybackState.playing,
        title: title,
        artist: artist,
      ));
      now = now.add(const Duration(minutes: 4));
    }

    setUp(() {
      now = DateTime(2026, 11, 1, 18);
      profile = MusicProfile(clock: () => now);
      settings = AppSettings();
      curator = Curator(settings: settings, profile: profile, brain: MusicBrain(profile: profile, settings: settings, clock: () => now));
      for (var r = 0; r < 3; r++) {
        for (var i = 0; i < 8; i++) {
          listen('Canción $i', 'Artista $i');
        }
      }
      for (var i = 0; i < 12; i++) {
        listen('Relleno $i', 'Otro $i');
      }
    });

    test('propone, y solo aplica lo que apruebas', () {
      final p = curator.propose(now: now.add(const Duration(hours: 6))).firstWhere((x) => x.listId == 'mix');
      expect(p.add, isNotEmpty);
      expect(p.remove, isEmpty);
      expect(curator.lists, isEmpty, reason: 'nada cambia sin aprobar');
      final keep = {p.add.first};
      curator.approve(p, add: keep, now: now);
      expect(curator.lists.single.items, [p.add.first]);
      expect(settings.curatedLists, hasLength(1));
    });

    test('descubrimientos externos se proponen aparte', () {
      final ps = curator.propose(now: now, extra: {'discover': ['Nueva — Alguien']});
      final d = ps.firstWhere((x) => x.listId == 'discover');
      expect(d.add, ['Nueva — Alguien']);
      expect(d.name, 'Descubrimientos');
    });

    test('borrar una lista', () {
      final p = curator.propose(now: now.add(const Duration(hours: 6))).first;
      curator.approve(p, now: now);
      curator.deleteList(p.listId);
      expect(curator.lists, isEmpty);
    });
  });
}
