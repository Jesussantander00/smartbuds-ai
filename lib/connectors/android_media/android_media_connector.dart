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
class AndroidMediaSource implements PlayerSource, SystemVolumeController {
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
  Future<bool> adjust({required bool up}) async =>
      await _channel.invokeMethod<bool>(
          'adjustSystemVolume', {'direction': up ? 'up' : 'down'}) ??
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
