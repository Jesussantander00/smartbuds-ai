import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/features/audio/sound_profiles.dart';
import 'package:smartbuds_ai/features/audio/transition_watcher.dart';
import 'package:smartbuds_ai/features/devices/headphone_diagnostics.dart';

class FakeFader implements VolumeFader {
  int volume = 70;
  final fades = <int>[];

  @override
  Future<int?> volumePercent() async => volume;

  @override
  Future<void> fadeVolume(int to, {int ms = 2000}) async {
    fades.add(to);
    volume = to;
  }
}

void main() {
  group('Ecualizador', () {
    test('lleva el perfil a las bandas reales del teléfono', () {
      // Bandas típicas de Android: 60, 230, 910, 3600, 14000 Hz.
      final mb = mapToDevice(presetById('bass').db, [60, 230, 910, 3600, 14000], -1500, 1500);
      expect(mb, [600, 400, 0, 0, 100]);
      // Un teléfono con otras bandas usa la más cercana y respeta su rango.
      final other = mapToDevice([12, 0, 0, 0, -12], [31, 500, 16000], -1000, 1000);
      expect(other, [1000, 0, -1000]);
    });

    test('perfil sugerido por tipo de música', () {
      expect(recommendedPresetFor('entrenar'), 'bass');
      expect(recommendedPresetFor('para concentrarme'), 'vocal');
      expect(recommendedPresetFor('dormir'), 'night');
      expect(recommendedPresetFor(null), 'flat');
    });

    test('perfiles por audífono y por música se guardan', () {
      final s = AppSettings()
        ..update(eqEnabled: true)
        ..setEqForDevice('Buds', 'bass')
        ..setEqForMood('dormir', 'night')
        ..setEqCustom([20, 1, 2, 3, -20]);
      final m = s.toMap();
      expect(m['eqEnabled'], isTrue);
      expect(m['eqByDevice'], {'Buds': 'bass'});
      expect(m['eqByMood'], {'dormir': 'night'});
      expect(s.eqCustom.first, 12, reason: 'máximo ±12 dB');
    });
  });

  group('Transiciones al final de la canción', () {
    late DateTime now;
    late AppSettings settings;
    late FakeFader fader;
    late TransitionWatcher w;

    PlayerStatus song(String title, {int pos = 0, int dur = 200000, bool playing = true}) => PlayerStatus(
          playerId: 'sp',
          packageName: 'sp',
          appName: 'Spotify',
          state: playing ? PlaybackState.playing : PlaybackState.paused,
          title: title,
          artist: 'X',
          positionMs: pos,
          durationMs: dur,
          lastActiveAt: now,
        );

    setUp(() {
      now = DateTime(2026, 11, 13, 21);
      settings = AppSettings()..update(smoothTransitions: true);
      fader = FakeFader();
      w = TransitionWatcher(settings: settings, fader: fader, clock: () => now);
    });

    tearDown(() => w.dispose());

    test('baja al final y sube cuando empieza la siguiente', () async {
      await w.update(song('A', pos: 100000));
      expect(fader.fades, isEmpty);
      await w.update(song('A', pos: 197000)); // faltan 3 s
      expect(fader.fades, [25]); // 70 × 0,35
      expect(w.fading, isTrue);
      await w.update(song('B'));
      expect(fader.fades, [25, 70]);
      expect(w.fading, isFalse);
    });

    test('apagado o sin duración no hace nada', () async {
      settings.update(smoothTransitions: false);
      await w.update(song('A', pos: 198000));
      settings.update(smoothTransitions: true);
      await w.update(PlayerStatus(
          playerId: 'sp', packageName: 'sp', appName: 'S', state: PlaybackState.playing, title: 'C', artist: 'X'));
      expect(fader.fades, isEmpty);
    });

    test('si pausas mientras baja, vuelve el volumen', () async {
      await w.update(song('A', pos: 198000));
      await w.update(song('A', pos: 198500, playing: false));
      expect(fader.fades, [25, 70]);
    });
  });

  test('diagnóstico: sesiones, cortes de la semana y consejos', () {
    final s = AppSettings();
    final now = DateTime(2026, 11, 13, 20);
    // 6 conexiones cortas de 1 minuto hoy.
    for (var i = 0; i < 6; i++) {
      final t = now.subtract(Duration(hours: 6 - i));
      s.logConnection(true, 'Buds', t);
      s.logConnection(false, 'Buds', t.add(const Duration(minutes: 1)));
    }
    final r = HeadphoneReport.from(s, now: now).single;
    expect(r.connections, 6);
    expect(r.dropsWeek, 6);
    expect(r.averageSession, const Duration(minutes: 1));
    expect(r.advice.first, contains('Se cortan seguido'));
  });
}
