import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/core/settings/app_settings.dart';

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
}
