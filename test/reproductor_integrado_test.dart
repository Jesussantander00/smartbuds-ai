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

/// Motor de mentira: anota lo que le piden.
class FakeEngine extends PlaybackEngine {
  final calls = <String>[];
  @override
  Future<void> load(InAppTrack track) async {
    calls.add('load:${track.id}');
    onState?.call(const EngineState(PlaybackState.playing, positionMs: 0, durationMs: 200000));
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(int positionMs) async => calls.add('seek:$positionMs');
  @override
  Future<void> setVolume(int percent) async => calls.add('vol:$percent');
}

class FakeCatalog extends InAppCatalog {
  FakeCatalog(this.source, this.items);
  @override
  final InAppSource source;
  final List<InAppTrack> items;
  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async => items;
}

InAppTrack yt(String id, String title) =>
    InAppTrack(id: 'yt:$id', source: InAppSource.youtube, title: title, videoId: id);
InAppTrack audius(String id, String title, String artist) =>
    InAppTrack(id: 'audius:$id', source: InAppSource.audius, title: title, artist: artist, streamUrl: 'https://a/$id');
InAppTrack preview(String id, String title, String artist) => InAppTrack(
    id: 'deezer:$id', source: InAppSource.deezerPreview, title: title, artist: artist, streamUrl: 'https://d/$id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('qué suena dentro de SmartBuds', () {
    test('completa (YouTube o Audius que coincide) antes que vista previa; Audius ajeno no se finge', () {
      final a = audius('1', 'Lofi para estudiar', 'Beatmaker');
      final p = preview('2', 'Normal', 'Feid');
      final order = InAppSource.values;
      expect(MusicCatalog.merge([a, p, yt('abc123', 'Normal')], 'Feid Normal', order).first.best.source,
          InAppSource.deezerPreview,
          reason: 'el video sin artista no coincide con «Feid»; la vista previa sí');
      expect(MusicCatalog.merge([a, p], 'Feid Normal', order).map((r) => r.title), ['Normal'],
          reason: 'Audius ajeno se descarta');
      expect(MusicCatalog.merge([audius('3', 'Normal', 'Feid'), p], 'Feid Normal', order).single.best.source,
          InAppSource.audius);
      expect(MusicCatalog.merge(const [], 'x', order), isEmpty);
    });

    test('Audius: solo canciones reproducibles; Deezer: solo las que tienen vista previa', () {
      final au = AudiusCatalog.parse({
        'data': [
          {'id': 'a1', 'title': 'Libre', 'user': {'name': 'Ana'}, 'duration': 180, 'is_streamable': true},
          {'id': 'a2', 'title': 'Pago', 'user': {'name': 'B'}, 'is_stream_gated': true},
        ],
      }, 'https://host');
      expect(au.single.streamUrl, 'https://host/v1/tracks/a1/stream?app_name=SmartBudsAI');
      expect(au.single.durationMs, 180000);
      final dz = DeezerPreviewCatalog.parse({
        'data': [
          {'id': 1, 'title': 'Normal', 'preview': 'https://cdn/p.mp3', 'artist': {'name': 'Feid'}},
          {'id': 2, 'title': 'Sin', 'preview': ''},
        ],
      });
      expect(dz.single.isPreview, isTrue);
      expect(dz.single.sourceLabel, 'Vista previa 30 s · Deezer');
    });
  });

  group('reproductor', () {
    late Map<InAppSource, FakeEngine> engines;
    late SmartBudsPlayer player;

    setUp(() {
      engines = {};
      player = SmartBudsPlayer(
        catalog: MusicCatalog([
          FakeCatalog(InAppSource.youtube, [yt('aaaaaa1', 'Uno Tema'), yt('aaaaaa2', 'Dos Tema')]),
        ]),
        engineFor: (s) => engines.putIfAbsent(s, FakeEngine.new),
      );
    });

    test('busca, pone la mejor y se presenta como «SmartBuds» (no como otra app)', () async {
      final t = await player.playQuery('tema');
      expect(t!.id, 'yt:aaaaaa1');
      expect(engines[InAppSource.youtube]!.calls.first, 'load:yt:aaaaaa1');
      expect(player.status!.appName, 'SmartBuds');
      expect(player.status!.isPlaying, isTrue);
      expect(player.isActive, isTrue);
    });

    test('video que YouTube no deja incrustar: pasa al siguiente resultado', () async {
      await player.playQuery('tema');
      engines[InAppSource.youtube]!.onState!(const EngineState(PlaybackState.stopped, error: 'not_embeddable'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(player.current!.id, 'yt:aaaaaa2');
    });

    test('al terminar avisa (para que siga la cola)', () async {
      var ended = 0;
      player.onEnded = () => ended++;
      await player.playQuery('tema');
      engines[InAppSource.youtube]!.onState!(const EngineState(PlaybackState.stopped, ended: true));
      expect(ended, 1);
      expect(player.status!.state, PlaybackState.stopped);
    });

    test('minimizar el video lo pausa; reanudar lo vuelve a mostrar', () async {
      await player.playQuery('tema');
      await player.toggleMinimized();
      expect(engines[InAppSource.youtube]!.calls, contains('pause'));
      await player.resume();
      expect(player.minimized, isFalse);
    });

    test('anterior: si va avanzada vuelve al inicio', () async {
      await player.playQuery('tema');
      player.positionMs = 30000;
      await player.previous();
      expect(engines[InAppSource.youtube]!.calls.last, 'seek:0');
    });
  });

  group('Jarvis controla el reproductor integrado', () {
    late Assistant a;
    late FakeEngine engine;
    late List<String> spoken;
    late AppSettings settings;

    setUp(() {
      spoken = [];
      const channel = MethodChannel('smartbuds/voice-inapp-test');
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
      settings = AppSettings();
      a = Assistant(controller: controller, profile: MusicProfile(), settings: settings);
      a.voice = VoiceEngine(onCommand: (_) async {}, method: channel);
      engine = FakeEngine();
      a.inApp = SmartBudsPlayer(
        catalog: MusicCatalog([
          FakeCatalog(InAppSource.audius, [audius('1', 'Normal', 'Feid'), audius('2', 'Normal Remix', 'Feid')]),
        ]),
        engineFor: (_) => engine,
      );
    });

    test('«busca Feid Normal» suena dentro de SmartBuds', () async {
      await a.handleSearch(SearchRequest('Feid Normal'));
      expect(engine.calls.first, 'load:audius:1');
      expect(spoken.last, contains('Reproduciendo Normal — Feid'));
      expect(a.active!.appName, 'SmartBuds');
    });

    test('«en Spotify» abre esa app a propósito (no el reproductor integrado)', () async {
      await a.handleSearch(SearchRequest('Normal', appPackage: 'com.spotify.music', appName: 'Spotify'));
      expect(engine.calls, isEmpty);
    });

    test('con el ajuste apagado, no reproduce dentro', () async {
      settings.update(playInApp: false);
      await a.handleSearch(SearchRequest('Feid Normal'));
      expect(engine.calls, isEmpty);
    });

    test('voz: «cambia» usa la cola primero; «sube» cambia el volumen de SmartBuds, no el del teléfono', () async {
      await a.handleSearch(SearchRequest('Feid Normal'));
      await a.handleCommand(MusicCommand.volumeDown);
      expect(a.inApp!.volume, 85);
      await a.handleCommand(MusicCommand.pause);
      expect(engine.calls, contains('pause'));
      await a.handleCommand(MusicCommand.next);
      expect(engine.calls.last, 'vol:85');
      expect(a.inApp!.current!.id, 'audius:2');
    });
  });

  group('Jarvis al abrir la app', () {
    late List<String> calls;
    late bool permitted;
    const channel = MethodChannel('smartbuds/voice-open-test');

    setUp(() {
      calls = [];
      permitted = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'hasPermission' || call.method == 'requestPermission') return permitted;
        return true;
      });
    });

    test('con permiso empieza solo; sin permiso muestra «Micrófono sin permiso»', () async {
      final v = VoiceEngine(onCommand: (_) async {}, method: channel);
      await v.autoStart();
      expect(calls, contains('start'));
      await v.stop();
      v.dispose();
      permitted = false;
      calls.clear();
      final w = VoiceEngine(onCommand: (_) async {}, method: channel);
      await w.autoStart();
      expect(calls, isNot(contains('start')));
      expect(w.jarvisState, JarvisState.noPermission);
      w.dispose();
    });

    test('recuerda si apagaste la escucha a propósito', () async {
      final prefs = <bool>[];
      final v = VoiceEngine(onCommand: (_) async {}, method: channel)..onPreferenceChanged = prefs.add;
      await v.start();
      await v.stop();
      v.handleEvent({'type': 'state', 'listening': false, 'stopped': true});
      expect(prefs, [true, false, false]);
      v.dispose();
    });
  });
}
