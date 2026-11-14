import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/capability_manager/capability_manager.dart';
import 'package:smartbuds_ai/core/command_router/command_router.dart';
import 'package:smartbuds_ai/core/connector_manager.dart';
import 'package:smartbuds_ai/core/player_detector/active_player_detector.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/assistant/assistant.dart';
import 'package:smartbuds_ai/features/devices/detected_player_controller.dart';
import 'package:smartbuds_ai/features/discovery/journey.dart';
import 'package:smartbuds_ai/features/music_profile/music_profile.dart';

import 'fakes.dart';

/// PR #42: viajes musicales con progresión de energía.
void main() {
  test('arco: empieza tranquilo, llega al pico y termina relajado, sin saltos bruscos', () {
    final c = JourneyPlanner.curve(JourneyShape.arco, 13);
    expect(c.first, 1);
    expect(c.last, 1);
    expect(c.reduce(max), 5);
    for (var i = 1; i < c.length; i++) {
      expect((c[i] - c[i - 1]).abs(), lessThanOrEqualTo(2), reason: 'paso $i');
    }
  });

  test('subida sube siempre y bajada baja siempre', () {
    final up = JourneyPlanner.curve(JourneyShape.subida, 8);
    final down = JourneyPlanner.curve(JourneyShape.bajada, 8, start: 4);
    for (var i = 1; i < 8; i++) {
      expect(up[i], greaterThanOrEqualTo(up[i - 1]));
      expect(down[i], lessThanOrEqualTo(down[i - 1]));
    }
    expect(up.last, 5);
    expect(down.last, 0);
  });

  MusicProfile profileWith() {
    final p = MusicProfile();
    void add(String title, String artist, String mood) {
      final key = MusicProfile.keyFor(title, artist);
      p.tracks[key] = TrackStats(key: key, title: title, artist: artist)..completes = 3;
      (p.moodTracks[mood] ??= <String>{}).add(key);
    }

    add('Calma', 'Pedro Capó', 'tranquila');
    add('Suave', 'Morat', 'romántica');
    add('Feliz', 'Juanes', 'alegre');
    add('Perreo', 'Feid', 'de fiesta');
    add('Power', 'Kanye', 'para entrenar');
    return p;
  }

  test('usa tu música para cada tramo, sin repetir, y completa con búsquedas variadas', () {
    final j = JourneyPlanner.plan(profileWith(), JourneyShape.arco, minutes: 45, random: Random(1));
    expect(j.steps.length, 13);
    final yours = j.steps.where((s) => s.fromYourMusic).map((s) => s.query).toList();
    expect(yours.toSet().length, yours.length, reason: 'sin repetir');
    expect(yours, contains('Power Kanye'));
    // Las búsquedas de relleno no se repiten seguidas.
    for (var i = 1; i < j.steps.length; i++) {
      if (!j.steps[i].fromYourMusic) expect(j.steps[i].query, isNot(j.steps[i - 1].query));
    }
  });

  test('voz', () {
    const p = CommandParser();
    expect((p.parseIntent('viaje musical') as JourneyIntent).shape, 'arco');
    final h = p.parseIntent('haz un viaje musical de una hora') as JourneyIntent;
    expect(h.minutes, 60);
    expect((p.parseIntent('viaje musical de subida de treinta minutos') as JourneyIntent).minutes, 30);
    expect((p.parseIntent('bájame la energía') as JourneyIntent).shape, 'bajada');
    expect(p.parseIntent('sube la energía poco a poco'), isA<EnergyRampIntent>(), reason: 'se mantiene');
  });

  test('el asistente pone la primera, deja el resto en la cola y sigue el progreso', () async {
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
    final a = Assistant(controller: controller, profile: profileWith(), settings: AppSettings());
    final j = await a.startJourney(JourneyShape.subida, minutes: 20);
    expect(a.journey, isNotNull);
    expect(a.queue.length, j.steps.length - 1);
    a.cancelJourney();
    expect(a.journey, isNull);
    expect(a.queue, isEmpty);
  });
}
