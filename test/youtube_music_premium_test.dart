import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/connectors/connector_interface.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';
import 'search_test.dart' show FakeSearch, FakeFinder, routerWith, ytStatus;

/// «Usar mi YouTube Music Premium»: nunca abrir YouTube Music sin permiso.
void main() {
  group('router con allowOpen: false', () {
    test('sesión activa que acepta la canción: suena sin abrir nada', () async {
      final yt = FakeConnector(ytStatus('Luna'));
      final search = FakeSearch()..onSessionUri = (_) => yt.current = ytStatus('Ojalá');
      final r = await routerWith(FakeSource([yt]), search, finder: FakeFinder())
          .routeSearch('ojala', allowOpen: false);
      expect(r.outcome, CommandOutcome.verified);
      expect(search.opened, isEmpty);
      expect(search.returns, 0);
    });

    test('si haría falta abrir la app, NO la abre y pide permiso', () async {
      final yt = FakeConnector(ytStatus('Luna')); // la sesión no cambia de canción
      final search = FakeSearch();
      final r = await routerWith(FakeSource([yt]), search, finder: FakeFinder())
          .routeSearch('ojala', allowOpen: false);
      expect(r.outcome, CommandOutcome.needsConsent);
      expect(search.opened, isEmpty, reason: 'sin enlace directo');
      expect(search.modes, isNot(contains(SearchMode.intent)), reason: 'sin intención que abre la app');
    });

    test('YouTube Music cerrado (sin sesión): pide permiso sin intentar nada visible', () async {
      final search = FakeSearch();
      final r = await routerWith(FakeSource([]), search).routeSearch('ojala', allowOpen: false);
      expect(r.outcome, CommandOutcome.needsConsent);
      expect(search.calls, isEmpty);
      expect(search.opened, isEmpty);
    });
  });

  group('asistente', () {
    late FakeConnector yt;
    late FakeSearch search;
    late Assistant a;
    late AppSettings settings;

    setUp(() {
      yt = FakeConnector(ytStatus('Luna'));
      search = FakeSearch(onPlay: (mode, q) {
        if (mode == SearchMode.intent) yt.current = ytStatus('Ojalá');
      });
      final lastUsed = InMemoryLastUsedStore();
      final connectors = ConnectorManager([FakeSource([yt])]);
      final detector = ActivePlayerDetector(lastUsed: lastUsed);
      final capabilities = CapabilityManager();
      final router = CommandRouter(
        connectors: connectors,
        detector: detector,
        capabilities: capabilities,
        lastUsed: lastUsed,
        search: search,
      )
        ..searchSessionWait = const Duration(milliseconds: 50)
        ..searchIntentWait = const Duration(milliseconds: 50);
      final controller = DetectedPlayerController(
          connectors: connectors, detector: detector, capabilities: capabilities, router: router);
      settings = AppSettings()..update(useYouTubeMusic: true);
      a = Assistant(controller: controller, profile: MusicProfile(), settings: settings);
    });

    test('«busca» va a YouTube Music; si hay que abrirlo, pregunta y espera', () async {
      await a.handleSearch(SearchRequest('ojala'));
      expect(search.calls.first.$1, CommandRouter.defaultSearchPackage);
      expect(search.modes, [SearchMode.session], reason: 'solo el camino invisible');
      expect(a.pendingOpenActive?.query, 'ojala');
    });

    test('«ábrelo» autoriza y entonces sí se abre', () async {
      await a.handleSearch(SearchRequest('ojala'));
      await a.handleIntent(const CommandParser().parseIntent('ábrelo')!);
      expect(search.modes, contains(SearchMode.intent));
      expect(a.pendingOpen, isNull);
      expect(yt.current.title, 'Ojalá');
    });

    test('cancelar no abre nada', () async {
      await a.handleSearch(SearchRequest('ojala'));
      a.cancelOpen();
      await a.confirmOpen();
      expect(search.modes, isNot(contains(SearchMode.intent)));
    });

    test('sin el ajuste, la búsqueda por voz tampoco abre apps sin permiso', () async {
      settings.update(useYouTubeMusic: false);
      await a.handleSearch(SearchRequest('ojala'));
      expect(search.modes, isNot(contains(SearchMode.intent)));
      expect(a.pendingOpenActive, isNotNull);
    });
  });
}
