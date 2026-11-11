import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';
import 'package:smartbuds_ai/core/storage/json_store.dart';

void main() {
  test('detecta conexión inestable', () {
    final s = AppSettings();
    final t0 = DateTime(2026, 1, 1, 10);
    s.logConnection(true, 'Buds', t0);
    s.logConnection(false, 'Buds', t0.add(const Duration(minutes: 1)));
    s.logConnection(true, 'Buds', t0.add(const Duration(minutes: 2)));
    s.logConnection(false, 'Buds', t0.add(const Duration(minutes: 3)));
    expect(s.unstableConnection(t0.add(const Duration(minutes: 4))), isFalse);
    s.logConnection(false, 'Buds', t0.add(const Duration(minutes: 5)));
    expect(s.unstableConnection(t0.add(const Duration(minutes: 6))), isTrue);
    expect(s.unstableConnection(t0.add(const Duration(hours: 1))), isFalse);
    expect(s.connectionLog.first.connected, isFalse);
  });

  test('audífonos preferidos', () {
    final s = AppSettings();
    s.setPreferredHeadphone('Galaxy Buds');
    expect(s.preferredHeadphone, 'Galaxy Buds');
    s.setPreferredHeadphone(null);
    expect(s.preferredHeadphone, isNull);
  });

  test('cambiar de audífonos no cuenta como desconexión', () {
    final s = AppSettings();
    final t0 = DateTime(2026, 1, 1, 10);
    for (var i = 0; i < 3; i++) {
      final t = t0.add(Duration(minutes: i * 2));
      s.logConnection(false, 'Buds A', t);
      s.logConnection(true, 'Buds B', t.add(const Duration(seconds: 5)));
    }
    expect(s.realDisconnections(), isEmpty);
    expect(s.unstableConnection(t0.add(const Duration(minutes: 7))), isFalse);
  });

  test('el aviso no se repite después de «Entendido»', () {
    final s = AppSettings();
    final t0 = DateTime(2026, 1, 1, 10);
    for (var i = 0; i < 3; i++) {
      s.logConnection(false, 'Buds', t0.add(Duration(minutes: i)));
    }
    final now = t0.add(const Duration(minutes: 4));
    expect(s.showUnstableAlert(now), isTrue);
    s.dismissUnstable(now);
    expect(s.showUnstableAlert(now.add(const Duration(minutes: 10))), isFalse);
  });

  test('los preferidos se guardan al cerrar y abrir la app', () async {
    final store = MemoryJsonStore();
    final a = AppSettings(store: store);
    await a.load();
    a.setPreferredHeadphone('Galaxy Buds');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final b = AppSettings(store: store);
    await b.load();
    expect(b.preferredHeadphone, 'Galaxy Buds');
  });
}
