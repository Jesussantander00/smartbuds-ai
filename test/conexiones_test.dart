import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/connectors/deezer/similar_artists.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/discovery/connections.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// Deezer de mentira: sin internet en las pruebas.
class FakeFinder extends SimilarArtistsFinder {
  int calls = 0;
  @override
  Future<List<SimilarArtist>> similarTo(String artist, {int max = 6}) async {
    calls++;
    return switch (artist) {
      'Feid' => const [SimilarArtist('Ryan Castro', ['Mujeriego']), SimilarArtist('Blessd', ['Medallo'])],
      'Karol G' => const [SimilarArtist('Ryan Castro', ['Mujeriego']), SimilarArtist('Young Miko', ['Riri'])],
      _ => const [],
    };
  }

  @override
  Future<List<Collaboration>> collaboratorsOf(String artist) async => switch (artist) {
        'Feid' => const [Collaboration('ATL Jacob', 'Normal'), Collaboration('Karol G', 'X')],
        _ => const [],
      };
}

void main() {
  test('ordena: colaboración > estilo, y los «puentes» entre tus artistas suben', () {
    final list = ConnectionGraph.build(
      seeds: {'Feid': 1, 'Karol G': 0.8},
      known: {'feid', 'karol g'},
      collabs: {'Feid': const [Collaboration('ATL Jacob', 'Normal')]},
      similar: {
        'Feid': const [SimilarArtist('Ryan Castro', ['Mujeriego']), SimilarArtist('Blessd', [])],
        'Karol G': const [SimilarArtist('Ryan Castro', ['Mujeriego'])],
      },
    );
    expect(list.first.name, 'Ryan Castro', reason: 'conecta a Feid y Karol G');
    expect(list.first.reason, 'Estilo parecido a Feid y Karol G');
    expect(list.first.query, 'Mujeriego Ryan Castro');
    final atl = list.firstWhere((d) => d.name == 'ATL Jacob');
    expect(atl.reason, 'Colaboró con Feid en «Normal»');
    expect(list.indexOf(atl), lessThan(list.indexWhere((d) => d.name == 'Blessd')));
  });

  test('nunca recomienda lo que ya escuchas ni lo que bloqueaste', () {
    final list = ConnectionGraph.build(
      seeds: {'Feid': 1},
      known: {'feid', 'blessd'},
      blocked: {'ryan castro'},
      similar: {'Feid': const [SimilarArtist('Ryan Castro', []), SimilarArtist('Blessd', []), SimilarArtist('Feid', [])]},
    );
    expect(list, isEmpty);
  });

  test('voz', () {
    const p = CommandParser();
    expect(p.parseIntent('descubre por colaboraciones'), isA<ConnectionsIntent>());
    expect((p.parseIntent('colaboraciones de este artista') as ConnectionsIntent).current, isTrue);
    expect((p.parseIntent('¿Con quién ha colaborado Feid?') as ConnectionsIntent).artist, 'feid');
  });

  test('el asistente usa tus artistas principales y guarda el resultado 6 horas', () async {
    final lastUsed = InMemoryLastUsedStore();
    final connectors = ConnectorManager([FakeSource([])]);
    final detector = ActivePlayerDetector(lastUsed: lastUsed);
    final capabilities = CapabilityManager();
    final controller = DetectedPlayerController(
      connectors: connectors,
      detector: detector,
      capabilities: capabilities,
      router: CommandRouter(connectors: connectors, detector: detector, capabilities: capabilities, lastUsed: lastUsed),
    );
    final profile = MusicProfile();
    for (final (title, artist, n) in [('Normal', 'Feid', 6), ('Provenza', 'Karol G', 3)]) {
      final key = MusicProfile.keyFor(title, artist);
      profile.tracks[key] = TrackStats(key: key, title: title, artist: artist)..completes = n;
    }
    final finder = FakeFinder();
    final a = Assistant(controller: controller, profile: profile, settings: AppSettings(), similar: finder);
    final list = await a.discoverConnections();
    final names = list.map((d) => d.name).toList();
    expect(names.first, 'Ryan Castro');
    expect(names, containsAll(['ATL Jacob', 'Blessd', 'Young Miko']));
    expect(names, isNot(contains('Karol G')), reason: 'ya la escuchas');
    final before = finder.calls;
    await a.discoverConnections();
    expect(finder.calls, before, reason: 'usa lo guardado');
  });
}
