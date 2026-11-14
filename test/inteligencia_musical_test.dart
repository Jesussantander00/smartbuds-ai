import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/activity/activity.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/diagnostics/self_check.dart';
import 'package:smartbuds_ai/features/discovery/journey.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// PR #43: la inteligencia musical (#37 y #39–#42) funcionando junta.
void main() {
  late Assistant a;
  late AppSettings settings;
  late MusicProfile profile;
  late String tusa;

  setUp(() {
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
    profile = MusicProfile();
    String add(String title, String artist, String mood, {int completes = 4}) {
      final key = MusicProfile.keyFor(title, artist);
      profile.tracks[key] = TrackStats(key: key, title: title, artist: artist)..completes = completes;
      (profile.moodTracks[mood] ??= <String>{}).add(key);
      return key;
    }

    tusa = add('Tusa', 'Karol G', 'tranquila', completes: 9);
    add('Calma', 'Pedro Capó', 'tranquila');
    add('Lento', 'Morat', 'para concentrarte');
    add('Suave', 'Reik', 'romántica');
    add('Feliz', 'Juanes', 'alegre');
    add('Perreo', 'Feid', 'de fiesta');
    add('Power', 'Kanye', 'para entrenar');
    settings = AppSettings();
    a = Assistant(controller: controller, profile: profile, settings: settings);
  });

  void repeatTusa() {
    for (var i = 0; i < 6; i++) {
      profile.history.add(ListenEvent(DateTime.now().subtract(Duration(minutes: 10 * i)), tusa, ListenEventType.play));
    }
  }

  test('lo que se está repitiendo no entra en viajes ni en recomendaciones por actividad', () async {
    repeatTusa();
    expect(a.repeatAlerts.single.key, tusa);
    final j = await a.startJourney(JourneyShape.arco, minutes: 30);
    expect(j.steps.map((s) => s.query), isNot(contains('Tusa Karol G')));
    final picks = a.forActivity(Activity.descansar);
    expect(picks.map((p) => p.track.key), isNot(contains(tusa)));
    expect(picks, isNotEmpty, reason: 'hay otras tranquilas');
  });

  test('la cola inteligente no desordena un viaje musical', () async {
    settings.update(smartQueue: true);
    final j = await a.startJourney(JourneyShape.subida, minutes: 20);
    final before = [...a.queue];
    a.addToQueue(['Otra canción']);
    expect(a.queue.take(before.length), before, reason: 'el viaje sigue en su orden');
    expect(a.arrangeQueue(), contains('viaje musical en curso'));
    expect(a.journey, same(j));
  });

  test('un viaje no ensucia las listas por ambiente, pero la actividad sigue', () async {
    await a.startActivity(Activity.estudiar);
    expect(profile.currentMood, 'para concentrarte');
    await a.startJourney(JourneyShape.arco, minutes: 30);
    expect(profile.currentMood, isNull);
    expect(a.activity.activity, Activity.estudiar);
  });

  test('«termina el viaje» lo cierra y vacía su cola', () async {
    await a.startJourney(JourneyShape.arco, minutes: 30);
    await a.handleIntent(const CommandParser().parseIntent('termina el viaje')!);
    expect(a.journey, isNull);
    expect(a.queue, isEmpty);
  });

  test('las frases de voz nuevas no se pisan entre sí', () {
    const p = CommandParser();
    final expected = <String, Type>{
      'estoy estudiando': ActivityIntent,
      'terminé': ActivityIntent,
      'viaje musical': JourneyIntent,
      'termina el viaje': JourneyIntent,
      'bájame la energía': JourneyIntent,
      'sube la energía poco a poco': EnergyRampIntent,
      'ordena la cola': ArrangeQueueIntent,
      '¿estoy repitiendo mucho?': RepetitionIntent,
      'varía un poco': RepetitionIntent,
      'descubre por colaboraciones': ConnectionsIntent,
      'pon una de él': FollowUpArtistIntent,
      'no, la otra': CorrectionIntent,
      'haz un diagnóstico': DiagnoseIntent,
      'pon algo para estudiar': MoodIntent,
      'pon algo nuevo': DiscoverIntent,
      'cambia': CommandIntent,
    };
    for (final e in expected.entries) {
      expect(p.parseIntent(e.key).runtimeType, e.value, reason: e.key);
    }
  });

  test('el autodiagnóstico dice cuánto sabe de tu música', () async {
    a.onlineProbe = () async => true;
    final f = await a.selfCheck();
    final m = f.firstWhere((x) => x.area == CheckArea.musica);
    expect(m.isOk, isFalse, reason: 'solo 7 canciones');
    expect(m.title, 'Aún te conozco poco');
    final many = SelfCheck.run(SelfCheckInput(now: DateTime.now(), knownTracks: 40, energyKnown: 6));
    expect(many.firstWhere((x) => x.area == CheckArea.musica).title, 'Sé la energía de solo el 15 % de tu música');
  });
}
