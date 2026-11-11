import 'dart:convert';
import 'dart:io';

/// Reportes anónimos de errores (Supabase, tabla `app_errors`).
///
/// Sirve para saber qué falla en los teléfonos de otras personas: la voz no
/// entendió, un reproductor no respondió, la app se cerró… No envía audio ni
/// lo que dijiste, solo el tipo de error, un mensaje corto y el sistema.
/// Se puede apagar en Asistente → Ajustes.
class ErrorReporter {
  ErrorReporter({
    required this.url,
    required this.anonKey,
    required this.deviceId,
    required this.enabled,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String url;
  final String anonKey;
  final String deviceId;

  /// Se consulta en cada reporte (el ajuste puede cambiar mientras se usa).
  final bool Function() enabled;
  final HttpClient _client;

  /// Límite por sesión para no gastar datos si algo falla en bucle.
  static const maxPerSession = 25;
  int _sent = 0;
  final Set<String> _seen = {};

  /// Últimos errores en este teléfono (para el Centro de diagnóstico).
  /// Se guardan aunque los reportes estén apagados; nunca salen sin permiso.
  final List<({DateTime at, String kind, String message})> recent = [];

  Future<void> report(String kind, Object message) async {
    final text = '$message';
    final short = text.length > 500 ? text.substring(0, 500) : text;
    recent.insert(0, (at: DateTime.now(), kind: kind, message: short));
    if (recent.length > 30) recent.removeLast();
    if (!enabled() || _sent >= maxPerSession) return;
    if (!_seen.add('$kind|$short')) return; // el mismo error una vez por sesión
    _sent++;
    await _send(kind, short);
  }

  /// Reporte que la persona decide enviar desde la app (con su permiso
  /// explícito, aunque los reportes automáticos estén apagados).
  Future<bool> sendUserReport(String summary) =>
      _send('user_report', summary.length > 500 ? summary.substring(0, 500) : summary);

  Future<bool> _send(String kind, String short) async {
    try {
      final req = await _client
          .postUrl(Uri.parse('$url/rest/v1/app_errors'))
          .timeout(const Duration(seconds: 6));
      req.headers
        ..set('apikey', anonKey)
        ..set('Content-Type', 'application/json')
        ..set('Prefer', 'return=minimal');
      if (anonKey.startsWith('eyJ')) req.headers.set('Authorization', 'Bearer $anonKey');
      req.add(utf8.encode(jsonEncode({
        'device_id': deviceId,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'kind': kind,
        'message': short,
      })));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      return res.statusCode < 300;
    } catch (_) {
      // Sin internet: el reporte se pierde, no pasa nada.
      return false;
    }
  }
}
