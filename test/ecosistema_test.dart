import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/voice_engine/command_parser.dart';
import 'package:smartbuds_ai/features/devices/device_hub.dart';
import 'package:smartbuds_ai/features/smarthome/home_link.dart';

void main() {
  test('continuidad: lee la cola, el ambiente y el perfil del otro teléfono', () {
    final d = RemoteDevice.fromJson({
      'device_id': 'aaaa',
      'name': 'Tel',
      'platform': 'android',
      'title': 'Ojalá',
      'queue': ['Una', 2, 'Dos'],
      'mood': 'entrenar',
      'usage': 'estudio',
      'updated_at': DateTime(2026, 11, 13).toUtc().toIso8601String(),
    });
    expect(d.queue, ['Una', 'Dos']);
    expect(d.mood, 'entrenar');
    expect(d.usage, 'estudio');
    expect(RemoteDevice.fromJson({'device_id': 'b', 'updated_at': ''}).queue, isEmpty);
  });

  group('escritorios de Inicio', () {
    test('cada escritorio guarda su propio orden', () {
      final s = AppSettings();
      expect(s.activeDesktop, 'casa');
      s.setHomeSections(['queue', 'now']);
      s.setDesktop('trabajo');
      expect(s.homeSections, isNot(['queue', 'now']));
      s.setHomeSections(['search']);
      s.setDesktop('casa');
      expect(s.homeSections, ['queue', 'now']);
      expect((s.toMap()['desktops'] as Map)['trabajo'], ['search']);
    });

    test('cambia solo con el perfil de uso', () {
      expect(AppSettings.desktopForProfile('estudio'), 'estudio');
      expect(AppSettings.desktopForProfile('viaje'), 'carro');
      expect(AppSettings.desktopForProfile(null), 'casa');
    });
  });

  group('hogar inteligente', () {
    test('solo direcciones https y con nombre', () {
      expect(HomeLink.validate('Fiesta', 'https://casa.example/api/webhook/x'), isNull);
      expect(HomeLink.validate('Fiesta', 'http://192.168.1.2/hook'), contains('https'));
      expect(HomeLink.validate('', 'https://x.y'), contains('nombre'));
    });

    test('lo que se envía: solo canción, artista y ambiente', () {
      final p = HomeLink.payload('scene', name: 'Fiesta', title: 'Ojalá', artist: 'Ryan Castro', mood: 'fiesta',
          at: DateTime.utc(2026, 11, 13, 22));
      expect(p.keys.toSet(), {'source', 'event', 'scene', 'title', 'artist', 'mood', 'at'});
      expect(p['event'], 'scene');
    });

    test('escena que no existe o en modo privado: no envía', () async {
      final s = AppSettings()
        ..setHomeHooks([
          {'name': 'Fiesta', 'url': 'https://casa.example/hook', 'event': 'manual'},
        ]);
      final link = HomeLink(settings: s);
      expect(await link.scene('Dormir'), isFalse);
      s.setPrivateMode(true);
      expect(await link.scene('fiesta'), isFalse);
    });

    test('los avisos no viajan en la copia de seguridad', () {
      final s = AppSettings()
        ..setHomeHooks([
          {'name': 'A', 'url': 'https://x.y/z', 'event': 'track'},
        ]);
      expect(s.backupPreferences().containsKey('homeHooks'), isFalse);
    });

    test('voz: «escena Fiesta»', () {
      const p = CommandParser();
      expect((p.parseIntent('activa la escena Fiesta') as HomeSceneIntent).name, 'fiesta');
      expect((p.parseIntent('escena relajarme') as HomeSceneIntent).name, 'relajarme');
    });
  });
}
