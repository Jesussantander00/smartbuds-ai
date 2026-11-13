import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/settings/app_settings.dart';
import '../account/supabase_auth.dart';

/// Otro dispositivo de tu cuenta y lo que está sonando ahí.
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.title,
    this.artist,
    this.app,
    this.playing = false,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String platform;
  final String? title;
  final String? artist;
  final String? app;
  final bool playing;
  final DateTime updatedAt;

  /// Se reportó hace menos de 3 minutos.
  bool onlineAt(DateTime now) => now.difference(updatedAt) < const Duration(minutes: 3);

  factory RemoteDevice.fromJson(Map<String, dynamic> j) => RemoteDevice(
        id: j['device_id'] as String,
        name: (j['name'] as String?) ?? 'Dispositivo',
        platform: (j['platform'] as String?) ?? 'other',
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        app: j['app'] as String?,
        playing: j['playing'] == true,
        updatedAt: DateTime.tryParse('${j['updated_at']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Centro multidispositivo: cada teléfono con tu cuenta publica qué suena
/// (una fila que se sobrescribe, sin historial) y ve lo de los demás.
///
/// No manda órdenes a otros teléfonos: Android y iPhone no dejan que una app
/// controle la música de otro dispositivo sin estar abierta allá. Lo que sí
/// hace es «Continuar aquí»: buscar la misma canción en este teléfono.
class DeviceHub extends ChangeNotifier {
  DeviceHub({
    required this.url,
    required this.anonKey,
    required this.auth,
    required this.settings,
    HttpClient? client,
    DateTime Function()? clock,
  })  : _client = client ?? HttpClient(),
        _clock = clock ?? DateTime.now;

  final String url;
  final String anonKey;
  final SupabaseAuth auth;
  final AppSettings settings;
  final HttpClient _client;
  final DateTime Function() _clock;

  List<RemoteDevice> devices = [];
  String? error;
  bool loading = false;

  String? _lastKey;
  DateTime? _lastAt;

  static String get platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'ios'
          : 'other';

  /// Nombre de este teléfono (el que elegiste o uno por defecto).
  String get myName =>
      settings.deviceName ?? (Platform.isIOS ? 'iPhone' : Platform.isAndroid ? 'Teléfono Android' : 'Este dispositivo');

  /// Los otros dispositivos (sin este).
  List<RemoteDevice> get others => devices.where((d) => d.id != settings.deviceId).toList();

  /// Decide si hay que publicar: cambió la canción o el estado, o pasó 1 minuto
  /// (para seguir apareciendo «en línea»). Nunca en modo privado.
  @visibleForTesting
  bool shouldPublish(PlayerStatus? s) {
    if (!settings.signedIn || !settings.shareDevices || settings.privateMode) return false;
    final key = '${s?.title}|${s?.artist}|${s?.isPlaying}';
    final now = _clock();
    if (key == _lastKey && _lastAt != null && now.difference(_lastAt!) < const Duration(minutes: 1)) {
      return false;
    }
    _lastKey = key;
    _lastAt = now;
    return true;
  }

  /// Publica lo que suena en este teléfono (si toca).
  Future<void> publish(PlayerStatus? s) async {
    if (!shouldPublish(s)) return;
    try {
      await _call('POST', '/rest/v1/rpc/upsert_my_device', {
        'p_device_id': settings.deviceId,
        'p_name': myName,
        'p_platform': platform,
        'p_title': s?.title,
        'p_artist': s?.artist,
        'p_app': s?.appName,
        'p_playing': s?.isPlaying ?? false,
      });
    } catch (_) {
      // Sin conexión o falta el SQL: se intenta de nuevo en el próximo cambio.
      _lastKey = null;
    }
  }

  Future<void> refresh() async {
    if (!settings.signedIn) {
      devices = [];
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final rows = await _call('GET', '/rest/v1/user_devices?select=*&order=updated_at.desc') as List?;
      devices = [for (final r in rows ?? const []) RemoteDevice.fromJson((r as Map).cast<String, dynamic>())];
      error = null;
    } on DeviceHubException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Sin conexión. Intenta otra vez.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Quita un dispositivo que ya no usas (vuelve a aparecer si se abre la app allá).
  Future<void> remove(RemoteDevice d) async {
    try {
      await _call('DELETE', '/rest/v1/user_devices?device_id=eq.${Uri.encodeQueryComponent(d.id)}');
      devices = devices.where((x) => x.id != d.id).toList();
      error = null;
    } on DeviceHubException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Sin conexión. Intenta otra vez.';
    }
    notifyListeners();
  }

  /// Deja de compartir: borra la fila de este teléfono.
  Future<void> forgetThisDevice() async {
    _lastKey = null;
    try {
      await _call('DELETE', '/rest/v1/user_devices?device_id=eq.${settings.deviceId}');
    } catch (_) {}
    devices = devices.where((x) => x.id != settings.deviceId).toList();
    notifyListeners();
  }

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    final token = await auth.validToken();
    if (token == null) throw const DeviceHubException('Entra con tu cuenta para ver tus dispositivos.');
    final req = await _client.openUrl(method, Uri.parse('$url$path')).timeout(const Duration(seconds: 8));
    req.headers
      ..set('apikey', anonKey)
      ..set('Authorization', 'Bearer $token')
      ..set('Content-Type', 'application/json');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      var msg = text;
      try {
        final j = jsonDecode(text);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (_) {}
      if (res.statusCode == 404 || msg.contains('does not exist') || msg.contains('Could not find')) {
        throw const DeviceHubException('Falta activar el centro de dispositivos (supabase/dispositivos.sql).');
      }
      throw DeviceHubException(msg.length > 140 ? msg.substring(0, 140) : msg);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}

class DeviceHubException implements Exception {
  const DeviceHubException(this.message);
  final String message;
}
