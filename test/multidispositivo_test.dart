import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/models.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/account/supabase_auth.dart';
import 'package:smartbuds_ai/features/devices/device_hub.dart';

PlayerStatus song(String title, {bool playing = true}) => PlayerStatus(
      playerId: 'sp',
      packageName: 'sp',
      appName: 'Spotify',
      state: playing ? PlaybackState.playing : PlaybackState.paused,
      title: title,
      artist: 'Feid',
    );

void main() {
  test('«modo carro» entra y sale por voz', () {
    const p = CommandParser();
    expect((p.parseIntent('modo carro') as CarModeIntent).on, isTrue);
    expect((p.parseIntent('modo automóvil') as CarModeIntent).on, isTrue);
    expect((p.parseIntent('voy a manejar') as CarModeIntent).on, isTrue);
    expect((p.parseIntent('sal del modo carro') as CarModeIntent).on, isFalse);
  });

  test('marcar el Bluetooth del carro y nombre del teléfono', () {
    final s = AppSettings();
    expect(s.carAutoOpen, isTrue);
    s.setCarDevice('Mazda', true);
    expect(s.carDevices, contains('Mazda'));
    s.setCarDevice('Mazda', false);
    expect(s.carDevices, isEmpty);
    s.setDeviceName('   ');
    expect(s.deviceName, isNull);
    s.setDeviceName('x' * 60);
    expect(s.deviceName!.length, 40);
    expect(s.shareDevices, isTrue);
  });

  group('Centro multidispositivo', () {
    late DateTime now;
    late AppSettings settings;
    late DeviceHub hub;

    setUp(() {
      now = DateTime(2026, 11, 12, 20);
      settings = AppSettings()
        ..authUserId = 'u1'
        ..authRefreshToken = 'r';
      final auth = SupabaseAuth(url: 'https://x.supabase.co', anonKey: 'k', settings: settings);
      hub = DeviceHub(url: auth.url, anonKey: 'k', auth: auth, settings: settings, clock: () => now);
    });

    test('publica al cambiar de canción y cada minuto, no en cada aviso', () {
      expect(hub.shouldPublish(song('A')), isTrue);
      expect(hub.shouldPublish(song('A')), isFalse);
      expect(hub.shouldPublish(song('A', playing: false)), isTrue);
      expect(hub.shouldPublish(song('B')), isTrue);
      now = now.add(const Duration(seconds: 61));
      expect(hub.shouldPublish(song('B')), isTrue);
    });

    test('nunca publica en modo privado, sin cuenta o si lo apagas', () {
      settings.setPrivateMode(true);
      expect(hub.shouldPublish(song('A')), isFalse);
      settings.setPrivateMode(false);
      settings.update(shareDevices: false);
      expect(hub.shouldPublish(song('A')), isFalse);
      settings.update(shareDevices: true);
      settings.authUserId = null;
      expect(hub.shouldPublish(song('A')), isFalse);
    });

    test('lee dispositivos, separa este teléfono y sabe si están en línea', () {
      settings.deviceId = 'aaaa';
      hub.devices = [
        RemoteDevice.fromJson({
          'device_id': 'aaaa',
          'name': 'Este',
          'platform': 'android',
          'updated_at': now.toUtc().toIso8601String(),
        }),
        RemoteDevice.fromJson({
          'device_id': 'bbbb',
          'name': 'iPad',
          'platform': 'ios',
          'title': 'Ojalá',
          'artist': 'Ryan Castro',
          'app': 'Apple Music',
          'playing': true,
          'updated_at': now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String(),
        }),
      ];
      expect(hub.others.map((d) => d.name), ['iPad']);
      final ipad = hub.others.single;
      expect(ipad.playing, isTrue);
      expect(ipad.onlineAt(now), isFalse);
      expect(hub.devices.first.onlineAt(now), isTrue);
    });
  });
}
