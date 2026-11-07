import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/connectors/connector_interface.dart';
import 'package:smartbuds_ai/connectors/youtube/youtube_search.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/core/voice_engine/voice_engine.dart';

import 'fakes.dart';

class FakeSearch implements SearchPlayer {
  FakeSearch({this.onPlay});

  /// Simula que la app empezó a reproducir (cambia el estado del conector).
  final void Function(SearchMode mode, String query)? onPlay;
  final calls = <(String, String)>[];
  final modes = <SearchMode>[];
  int returns = 0;
  final opened = <String>[];

  /// Simula que YouTube Music empieza a sonar al abrir el enlace directo.
  void Function(String uri)? onOpen;

  @override
  Future<void> returnToApp() async => returns++;

  final sessionUris = <String>[];

  /// Simula que la sesión acepta el enlace (sin abrir la app).
  void Function(String uri)? onSessionUri;

  @override
  Future<bool> playUriInSession(
      {required String packageName, required String uri, String? mediaId}) async {
    sessionUris.add(uri);
    onSessionUri?.call(uri);
    return true;
  }

  @override
  Future<bool> openUri({required String uri, required String packageName}) async {
    opened.add(uri);
    onOpen?.call(uri);
    return true;
  }

  @override
  Future<bool> playFromSearch({
    required String packageName,
    required String query,
    SearchMode mode = SearchMode.intent,
  }) async {
    calls.add((packageName, query));
    modes.add(mode);
    onPlay?.call(mode, query);
    return true;
  }
}

class FakeFinder implements SongFinder {
  @override
  Future<YouTubeHit?> find(String query) async =>
      YouTubeHit(videoId: 'abc123', title: 'Ojalá');

  @override
  Future<List<YouTubeHit>> findMany(String query, {int max = 10}) async =>
      [YouTubeHit(videoId: 'abc123', title: 'Ojalá')];
}

CommandRouter routerWith(FakeSource source, FakeSearch search,
    {SongFinder? finder}) {
  final lastUsed = InMemoryLastUsedStore();
  return CommandRouter(
    connectors: ConnectorManager([source]),
    detector: ActivePlayerDetector(lastUsed: lastUsed, clock: () => t0),
    capabilities: CapabilityManager(),
    lastUsed: lastUsed,
    search: search,
    songFinder: finder,
  )
    ..searchSessionWait = const Duration(milliseconds: 50)
    ..searchIntentWait = const Duration(milliseconds: 50);
}

PlayerStatus ytStatus(String title) => status('YouTube Music',
    pkg: 'com.google.android.apps.youtube.music',
    state: PlaybackState.playing,
    title: title);

void main() {
  group('CommandParser.parseSearch', () {
    const p = CommandParser();

    test('«busca» + canción', () {
      expect(p.parseSearch('busca Ojalá de Ryan Castro')!.query,
          'ojala de ryan castro');
      expect(p.parseSearch('Búscame la canción Despierto')!.query, 'despierto');
      expect(p.parseSearch('busca ojala')!.appPackage, isNull);
    });

    test('«… en <app>» elige el reproductor', () {
      final r = p.parseSearch('busca Ojalá en Apple Music')!;
      expect(r.query, 'ojala');
      expect(r.appPackage, 'com.apple.android.music');
      expect(p.parseSearch('busca despierto en amazon')!.appName, 'Amazon Music');
      expect(p.parseSearch('busca luna en youtube music')!.appPackage,
          'com.google.android.apps.youtube.music');
    });

    test('sin «busca» o sin canción no es búsqueda', () {
      expect(p.parseSearch('cambia'), isNull);
      expect(p.parseSearch('busca'), isNull);
      expect(p.parseSearch('yo busco trabajo'), isNull);
    });
  });

  group('CommandRouter.routeSearch', () {
    test('si la sesión acepta la búsqueda, reproduce y se verifica', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch(onPlay: (mode, q) {
        if (mode == SearchMode.session) yt.current = ytStatus('Ojalá');
      });
      final r = await routerWith(FakeSource([yt]), search).routeSearch('ojala');
      expect(r.outcome, CommandOutcome.verified);
      expect(search.modes, [SearchMode.session]);
    });

    test('si la sesión no responde, intenta con la intención', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch(onPlay: (mode, q) {
        if (mode == SearchMode.intent) yt.current = ytStatus('Ojalá');
      });
      final r = await routerWith(FakeSource([yt]), search).routeSearch('ojala');
      expect(r.outcome, CommandOutcome.verified);
      expect(search.modes, [SearchMode.session, SearchMode.intent]);
      expect(search.returns, 1, reason: 'SmartBuds vuelve al frente');
    });

    test('con clave de YouTube: enlace directo, suena y vuelve a SmartBuds', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch()..onOpen = (_) => yt.current = ytStatus('Ojalá');
      final r = await routerWith(FakeSource([yt]), search, finder: FakeFinder())
          .routeSearch('ojala');
      expect(r.outcome, CommandOutcome.verified);
      expect(search.opened, ['https://music.youtube.com/watch?v=abc123']);
      expect(search.modes, isEmpty, reason: 'no hizo falta buscar en la app');
      expect(search.returns, 1);
    });

    test('si la sesión acepta el enlace, suena sin abrir YouTube Music', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch()
        ..onSessionUri = (_) => yt.current = ytStatus('Ojalá');
      final r = await routerWith(FakeSource([yt]), search, finder: FakeFinder())
          .routeSearch('ojala');
      expect(r.outcome, CommandOutcome.verified);
      expect(search.sessionUris, ['https://music.youtube.com/watch?v=abc123']);
      expect(search.opened, isEmpty, reason: 'no se abrió la pantalla');
      expect(search.returns, 0);
    });

    test('YouTubeSearch.parse lee el primer resultado', () {
      final hit = YouTubeSearch.parse(
          '{"items":[{"id":{"videoId":"xyz"},"snippet":{"title":"Ojalá","channelTitle":"Ryan Castro"}}]}');
      expect(hit!.videoId, 'xyz');
      expect(hit.channel, 'Ryan Castro');
      expect(YouTubeSearch.parse('{"items":[]}'), isNull);
    });

    test('app pedida por voz aunque otra esté sonando', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch();
      await routerWith(FakeSource([yt]), search).routeSearch('ojala',
          appPackage: 'com.apple.android.music', appName: 'Apple Music');
      expect(search.calls.single.$1, 'com.apple.android.music');
      expect(search.modes, [SearchMode.intent],
          reason: 'Apple Music no tiene sesión activa');
    });

    test('si solo abre resultados, lo dice (no finge que reprodujo)', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch();
      final r = await routerWith(FakeSource([yt]), search).routeSearch('ojala');
      expect(r.outcome, CommandOutcome.sentUnverified);
      expect(r.message, contains('no empezó a reproducirla'));
    });

    test('sin reproductor activo usa YouTube Music', () async {
      final search = FakeSearch();
      await routerWith(FakeSource([]), search).routeSearch('despierto');
      expect(search.calls.single.$1, CommandRouter.defaultSearchPackage);
    });

    test('Spotify por voz: búsqueda bloqueada por política', () async {
      final sp = FakeConnector(status('Spotify',
          pkg: 'com.spotify.music', state: PlaybackState.playing));
      final search = FakeSearch();
      final r = await routerWith(FakeSource([sp]), search).routeSearch('ojala');
      expect(r.outcome, CommandOutcome.notAllowed);
      expect(search.calls, isEmpty);
    });
  });

  test('VoiceEngine: «busca …» llama a onSearch y no a onCommand', () {
    final commands = <MusicCommand>[];
    final searches = <String>[];
    final engine = VoiceEngine(
      onCommand: (c) async => commands.add(c),
      onSearch: (r) async => searches.add(r.query),
    );
    engine.handleEvent(
        {'type': 'final', 'session': 1, 'texts': ['busca ojalá ryan castro']});
    expect(searches, ['ojala ryan castro']);
    expect(commands, isEmpty);
  });
}
