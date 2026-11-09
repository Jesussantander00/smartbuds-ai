import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../connector_interface.dart';

/// Puente con el módulo Kotlin `MediaSessionConnector`.
class AndroidMediaChannel {
  static const method = MethodChannel('smartbuds/media');
  static const events = EventChannel('smartbuds/media/events');
}

/// Fuente Android: consulta las sesiones activas mediante
/// MediaSessionManager (requiere acceso a notificaciones).
class AndroidMediaSource
    implements PlayerSource, SystemVolumeController, SearchPlayer {
  AndroidMediaSource({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? AndroidMediaChannel.method,
        _events = events ?? AndroidMediaChannel.events;

  final MethodChannel _channel;
  final EventChannel _events;

  /// Sesiones más recientes, ya sean pedidas o recibidas por evento.
  List<Map<dynamic, dynamic>> _cache = const [];

  @override
  String get sourceId => 'android_media';

  @override
  Future<String?> missingPermission() async {
    final granted =
        await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false;
    return granted
        ? null
        : 'Activa el acceso a notificaciones de SmartBuds AI para detectar '
            'el reproductor activo.';
  }

  /// Salta a [positionMs] o mueve [deltaMs] en la canción del reproductor.
  Future<bool> seek(String playerId, {int? positionMs, int? deltaMs}) async {
    try {
      return await _channel.invokeMethod<bool>('seek', {
            'playerId': playerId,
            'positionMs': positionMs,
            'deltaMs': deltaMs,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Menú «Compartir» del sistema con [text].
  Future<bool> shareText(String text) async {
    try {
      return await _channel.invokeMethod<bool>('shareText', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// iPhone: permiso para controlar Apple Music (en Android no hace falta).
  Future<bool> hasMusicAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasMusicAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestMusicAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestMusicAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<T?> _safe<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  /// Volumen del sistema en porcentaje (0–100).
  Future<bool> setVolumePercent(int percent) async =>
      await _safe<bool>('setVolumePercent', {'percent': percent}) ?? false;

  Future<int?> volumePercent() => _safe<int>('getVolumePercent');

  /// Nombre de los audífonos conectados, o null si suena por el altavoz.
  Future<String?> outputDevice() => _safe<String>('getOutputDevice');

  /// Nivel de batería (0–100) y si está cargando.
  Future<({int level, bool charging})?> battery() async {
    final m = await _safe<Map<dynamic, dynamic>>('getBattery');
    if (m == null) return null;
    return (
      level: (m['level'] as num?)?.toInt() ?? 100,
      charging: m['charging'] == true,
    );
  }

  /// Pausa la música durante llamadas y la reanuda al colgar.
  Future<void> setCallPause(bool enabled) =>
      _safe<bool>('setCallPause', {'enabled': enabled});

  /// Pausa la música al desconectar los audífonos.
  Future<void> setPauseOnUnplug(bool enabled) =>
      _safe<bool>('setPauseOnUnplug', {'enabled': enabled});

  /// Dos toques al audífono = siguiente, tres = anterior.
  Future<void> setTapGestures(bool enabled) async {
    try {
      await _channel.invokeMethod('setTapGestures', {'enabled': enabled});
    } catch (_) {}
  }

  Future<void> openNotificationAccessSettings() =>
      _channel.invokeMethod('openNotificationAccessSettings');

  @override
  Future<List<MusicConnector>> discover() async {
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
            'getSessions') ??
        const [];
    _cache = raw;
    return [for (final m in raw) AndroidSessionConnector(this, m)];
  }

  @override
  Stream<void> get changes => _events.receiveBroadcastStream().map((event) {
        if (event is List) {
          _cache = event.cast<Map<dynamic, dynamic>>();
        }
      });

  Future<Map<dynamic, dynamic>?> _fetch(String playerId) async {
    final m = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getSession', {'playerId': playerId});
    return m;
  }

  Future<bool> _send(String playerId, MusicCommand command) async =>
      await _channel.invokeMethod<bool>(
        'sendCommand',
        {'playerId': playerId, 'command': command.wireName},
      ) ??
      false;

  @override
  Future<bool> adjust({required bool up}) async {
    // Tres pasos para que el cambio se note (Android tiene ~15 niveles).
    var ok = true;
    for (var i = 0; i < 3; i++) {
      ok = (await _channel.invokeMethod<bool>(
                  'adjustSystemVolume', {'direction': up ? 'up' : 'down'}) ??
              false) &&
          ok;
    }
    return ok;
  }

  @override
  Future<bool> playFromSearch({
    required String packageName,
    required String query,
    SearchMode mode = SearchMode.intent,
  }) async =>
      await _channel.invokeMethod<bool>('playFromSearch', {
        'packageName': packageName,
        'query': query,
        'mode': mode.name,
      }) ??
      false;

  @override
  Future<void> returnToApp() => _channel.invokeMethod('bringToFront');

  @override
  Future<bool> playUriInSession({
    required String packageName,
    required String uri,
    String? mediaId,
  }) async =>
      await _channel.invokeMethod<bool>('playUriInSession', {
        'packageName': packageName,
        'uri': uri,
        'mediaId': mediaId,
      }) ??
      false;

  @override
  Future<bool> openUri({required String uri, required String packageName}) async =>
      await _channel.invokeMethod<bool>(
          'openUri', {'uri': uri, 'packageName': packageName}) ??
      false;

  /// Últimos datos conocidos sin ir al canal nativo (para la UI).
  List<Map<dynamic, dynamic>> get cachedSessions => _cache;
}

/// Un conector por sesión multimedia activa.
class AndroidSessionConnector implements MusicConnector {
  AndroidSessionConnector(this._source, Map<dynamic, dynamic> initial)
      : playerId = initial['playerId'] as String,
        _last = initial;

  final AndroidMediaSource _source;
  Map<dynamic, dynamic> _last;

  @override
  final String playerId;

  @override
  String get connectorId => 'android_media';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlayerStatus> getStatus() async {
    final fresh = await _source._fetch(playerId);
    if (fresh == null) {
      throw StateError('La sesión $playerId ya no está activa.');
    }
    _last = fresh;
    return PlayerStatus.fromMap(fresh);
  }

  @override
  Future<Capabilities> getCapabilities() async =>
      Capabilities.fromWire((_last['actions'] as List?) ?? const []);

  @override
  Future<CommandResult> execute(MusicCommand command) async {
    final ok = await _source._send(playerId, command);
    return ok
        ? const CommandResult(CommandOutcome.sentUnverified, 'Enviado.')
        : const CommandResult(CommandOutcome.failed,
            'La sesión rechazó el comando o ya no está activa.');
  }
}
