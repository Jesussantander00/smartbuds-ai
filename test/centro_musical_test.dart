import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';
import 'package:smartbuds_ai/features/player/catalog.dart';
import 'package:smartbuds_ai/features/player/smartbuds_player.dart';

import 'fakes.dart';

/// PR #45: centro musical multiplataforma (proveedores → buscador unificado →
/// reproductor central → Jarvis).
class FakeProvider extends InAppCatalog {
  FakeProvider(this.source, this.items, {this.albumHits = const [], this.tracksOfAlbum = const []});
  @override
  final InAppSource source;
  final List<InAppTrack> items;
  final List<AlbumHit> albumHits;
  final List<InAppTrack> tracksOfAlbum;
  int searches = 0;
  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    searches++;
    return items;
  }

  @override
  Future<List<AlbumHit>> albums(String query, {int max = 6}) async => albumHits;
  @override
  Future<List<InAppTrack>> albumTracks(AlbumHit album) async => tracksOfAlbum;
}

class FakeEngine extends PlaybackEngine {
  final loaded = <String>[];
  @override
  Future<void> load(InAppTrack track) async {
    loaded.add(track.id);
    onState?.call(const EngineState(PlaybackState.playing, positionMs: 0));
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(int positionMs) async {}
  @override
  Future<void> setVolume(int percent) async {}
}

InAppTrack t(InAppSource s, String id, String title, String? artist, {String? album}) => InAppTrack(
      id: '${s.name}:$id',
      source: s,
      title: title,
      artist: artist,
      album: album,
      videoId: s == InAppSource.youtube ? id : null,
      streamUrl: s == InAppSource.youtube ? null : 'https://x/$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('auditoría de proveedores', () {
    test('lo que no se puede reproducir dentro nunca aparece como integrado', () {
      for (final p in ProviderRegistry.all) {
        if (p.playback == PlaybackKind.externalOnly) {
          expect(p.integrated, isFalse, reason: p.name);
          expect(p.source, isNull, reason: p.name);
        }
        if (p.integrated) expect(p.source, isNotNull, reason: p.name);
      }
      final names = ProviderRegistry.all.map((p) => p.id).toSet();
      expect(names, containsAll(['spotify', 'applemusic', 'youtube', 'deezer', 'soundcloud', 'audius', 'itunes']));
    });

    test('Apple (iTunes) se lee con vista previa, álbum y portada', () {
      final r = ITunesCatalog.parse({
        'results': [
          {
            'trackId': 7, 'trackName': "Hips Don't Lie", 'artistName': 'Shakira', 'collectionName': 'Oral Fixation',
            'previewUrl': 'https://audio-ssl.itunes.apple.com/p.m4a', 'artworkUrl100': 'https://a/100x100bb.jpg',
            'trackTimeMillis': 218000,
          },
          {'trackId': 8, 'trackName': 'Sin vista previa'},
        ],
      });
      expect(r.single.album, 'Oral Fixation');
      expect(r.single.artwork, 'https://a/300x300bb.jpg');
      expect(r.single.isPreview, isTrue);
      expect(r.single.sourceLabel, 'Vista previa 30 s · Apple');
    });

    test('Deezer: álbumes', () {
      final a = DeezerPreviewCatalog.parseAlbums({
        'data': [
          {'id': 123, 'title': 'Pies Descalzos', 'artist': {'name': 'Shakira'}, 'cover_medium': 'https://c'},
        ],
      });
      expect(a.single.title, 'Pies Descalzos');
      expect(a.single.provider, 'deezer');
    });
  });

  group('buscador unificado', () {
    final yt = t(InAppSource.youtube, 'aaaaaa1', "Shakira - Hips Don't Lie (Official 4K Video) ft. Wyclef Jean", null);
    final ytSplit = () {
      final (title, artist) = MusicCatalog.splitYouTube(yt.title, 'ShakiraVEVO');
      return t(InAppSource.youtube, 'aaaaaa1', title, artist);
    }();
    final dz = t(InAppSource.deezerPreview, '1', "Hips Don't Lie (feat. Wyclef Jean)", 'Shakira', album: 'Oral Fixation');
    final it = t(InAppSource.itunesPreview, '2', "Hips Don't Lie", 'Shakira');
    final au = t(InAppSource.audius, '3', 'Lofi beats', 'Nadie');

    test('YouTube «Artista - Canción (Video oficial)» se separa bien', () {
      expect(ytSplit.title, "Hips Don't Lie ft. Wyclef Jean");
      expect(ytSplit.artist, 'Shakira');
    });

    test('quita duplicados: una sola fila con varias fuentes, la completa primero', () {
      final r = MusicCatalog.merge([dz, it, ytSplit, au], 'Shakira', InAppSource.values);
      expect(r, hasLength(1), reason: 'Audius ajeno fuera; tres fuentes = una canción');
      expect(r.single.options.map((o) => o.source),
          [InAppSource.youtube, InAppSource.deezerPreview, InAppSource.itunesPreview]);
      expect(r.single.album, 'Oral Fixation');
      expect(r.single.availability, 'Completa en SmartBuds');
    });

    test('solo con vistas previas lo dice claramente', () {
      final r = MusicCatalog.merge([dz, it], 'Shakira', InAppSource.values).single;
      expect(r.hasFull, isFalse);
      expect(r.availability, 'Solo vista previa de 30 s en SmartBuds');
    });

    test('la prioridad de fuentes es configurable (entre completas)', () {
      final a2 = t(InAppSource.audius, '9', "Hips Don't Lie", 'Shakira');
      final r = MusicCatalog.merge([ytSplit, a2], 'Shakira', [InAppSource.audius, InAppSource.youtube]).single;
      expect(r.best.source, InAppSource.audius);
    });

    test('búsqueda por álbum y por artista', () async {
      final c = MusicCatalog([
        FakeProvider(InAppSource.deezerPreview, [dz],
            albumHits: const [AlbumHit(id: '123', title: 'Oral Fixation', artist: 'Shakira', provider: 'deezer')]),
      ]);
      expect((await c.albums('Oral Fixation')).single.title, 'Oral Fixation');
      expect((await c.search('Oral Fixation')).single.title, contains("Hips Don't Lie"), reason: 'coincide por álbum');
      expect((await c.search('Shakira')).single.artist, 'Shakira');
    });
  });

  group('Jarvis con el reproductor central', () {
    late Assistant a;
    late FakeEngine engine;
    late List<String> spoken;
    late List<String> routed;

    setUp(() {
      spoken = [];
      routed = [];
      const channel = MethodChannel('smartbuds/voice-centro-test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'speak') spoken.add((call.arguments as Map)['text'] as String);
        return true;
      });
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
      a = Assistant(controller: controller, profile: MusicProfile(), settings: AppSettings());
      a.voice = VoiceEngine(onCommand: (_) async {}, method: channel);
      engine = FakeEngine();
      a.inApp = SmartBudsPlayer(
        catalog: MusicCatalog([
          FakeProvider(InAppSource.audius, [
            t(InAppSource.audius, 'a1', 'Ojos Así', 'Shakira'),
            t(InAppSource.audius, 'a2', 'Antología', 'Shakira'),
          ]),
          FakeProvider(InAppSource.deezerPreview, [
            t(InAppSource.deezerPreview, 'd1', 'Ojos Así', 'Shakira'),
            t(InAppSource.deezerPreview, 'd3', 'Inevitable', 'Shakira'),
          ], albumHits: const [AlbumHit(id: '5', title: 'Dónde Están los Ladrones', artist: 'Shakira', provider: 'deezer')],
              tracksOfAlbum: [
                t(InAppSource.deezerPreview, 'd3', 'Inevitable', 'Shakira'),
                t(InAppSource.deezerPreview, 'd1', 'Ojos Así', 'Shakira'),
              ]),
        ]),
        engineFor: (_) => engine,
      );
      a.inApp!.onOpenExternal = (q) async => routed.add(q);
    });

    Future<void> say(String text) => a.handleIntent(const CommandParser().parseIntent(text) ??
        SearchIntent(SearchRequest(text)));

    test('«busca música de Shakira» suena dentro; «reproduce la segunda»; «otra versión»; «agrega esta a la cola»',
        () async {
      await a.handleSearch(SearchRequest('Shakira'));
      expect(engine.loaded.last, 'audius:a1', reason: 'completa antes que vista previa');
      await say('reproduce la segunda');
      expect(engine.loaded.last, 'audius:a2');
      await say('la primera');
      await say('busca otra versión');
      expect(engine.loaded.last, 'deezerPreview:d1', reason: 'otra fuente de la misma canción');
      await say('agrega esta canción a la cola');
      expect(a.queue, ['Ojos Así Shakira']);
    });

    test('«otra del mismo artista» pone una distinta a la que suena', () async {
      await a.handleSearch(SearchRequest('Ojos Así Shakira'));
      final first = engine.loaded.last;
      await a.handleIntent(const ArtistIntent('Shakira'));
      expect(engine.loaded.last, isNot(first));
    });

    test('«pon el álbum …»: la primera ya y el resto en la cola', () async {
      await say('pon el álbum dónde están los ladrones');
      expect(a.queue, ['Ojos Así Shakira']);
      expect(spoken.any((s) => s.contains('2 canciones')), isTrue);
      expect(engine.loaded, isNotEmpty);
    });

    test('sin fuente integrada: lo dice y NO abre otra app (solo con el botón)', () async {
      (a.inApp!.catalog.catalogs.first as FakeProvider).items.clear();
      (a.inApp!.catalog.catalogs.last as FakeProvider).items.clear();
      await a.handleSearch(SearchRequest('canción inexistente'));
      expect(spoken.last, contains('No puedo reproducir'));
      expect(routed, isEmpty);
      expect(a.inApp!.panelOpen, isTrue);
    });

    test('voz: frases nuevas', () {
      const p = CommandParser();
      expect((p.parseIntent('Reproduce la primera canción') as ResultPickIntent).index, 1);
      expect((p.parseIntent('pon la tercera') as ResultPickIntent).index, 3);
      expect(p.parseIntent('busca otra versión'), isA<OtherVersionIntent>());
      expect(p.parseIntent('agrega esta canción a la cola'), isA<QueueCurrentIntent>());
      expect((p.parseIntent('pon el disco pies descalzos') as AlbumIntent).query, 'pies descalzos');
      expect(p.parseIntent('pausa'), isA<CommandIntent>(), reason: 'lo de antes sigue igual');
      expect(p.parseIntent('primera'), isNull, reason: 'una palabra suelta no dispara nada');
    });
  });
}
