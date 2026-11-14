import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/settings/app_settings.dart';

/// Hogar inteligente por medio de TUS servicios (Home Assistant, IFTTT,
/// Node-RED…): SmartBuds avisa a una dirección (webhook) que tú creaste y ese
/// servicio enciende luces, cambia colores o lo que hayas programado.
///
/// Límite honesto: SmartBuds no controla bombillos directamente (Hue, Google
/// Home o Alexa exigen registrar la app en sus nubes). Solo envía: canción,
/// artista y ambiente. Nunca en modo privado.
class HomeLink extends ChangeNotifier {
  HomeLink({required this.settings, HttpClient? client, DateTime Function()? clock})
      : _client = client ?? HttpClient(),
        _clock = clock ?? DateTime.now;

  final AppSettings settings;
  final HttpClient _client;
  final DateTime Function() _clock;

  /// Resultado del último envío por aviso (nombre → texto).
  final Map<String, String> lastResult = {};
  final Map<String, DateTime> _lastSent = {};

  static const events = {'track': 'Cada canción', 'mood': 'Cambio de ambiente', 'manual': 'Escena (por voz o automatización)'};

  /// Solo direcciones https completas (nada de direcciones locales sin cifrar).
  static String? validate(String name, String url) {
    if (name.trim().isEmpty) return 'Ponle un nombre (así lo llamas por voz: «escena Fiesta»).';
    final u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return 'La dirección debe empezar con https://';
    return null;
  }

  bool get _allowed => settings.moduleOn('smarthome') && !settings.privateMode;

  /// Envía a todos los avisos de ese tipo. Máximo uno cada 5 s por aviso.
  Future<void> notify(String event, {String? title, String? artist, String? mood}) async {
    if (!_allowed) return;
    for (final h in settings.homeHooks) {
      if (h['event'] != event) continue;
      await _send(h, event, title: title, artist: artist, mood: mood);
    }
  }

  /// «Escena Fiesta»: envía al aviso manual con ese nombre. false si no existe.
  Future<bool> scene(String name, {String? title, String? artist, String? mood}) async {
    final n = name.trim().toLowerCase();
    final h = settings.homeHooks.where((x) => x['event'] == 'manual' && (x['name'] ?? '').toLowerCase() == n).firstOrNull;
    if (h == null || !_allowed) return false;
    return _send(h, 'scene', title: title, artist: artist, mood: mood, force: true);
  }

  /// Probar un aviso desde la pantalla.
  Future<bool> test(Map<String, String> h) => _send(h, 'test', title: 'Prueba de SmartBuds', force: true);

  @visibleForTesting
  static Map<String, dynamic> payload(String event, {String? name, String? title, String? artist, String? mood, DateTime? at}) => {
        'source': 'smartbuds',
        'event': event,
        if (name != null) 'scene': name,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (mood != null) 'mood': mood,
        'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      };

  Future<bool> _send(Map<String, String> h, String event,
      {String? title, String? artist, String? mood, bool force = false}) async {
    final name = h['name'] ?? '';
    final url = h['url'] ?? '';
    if (validate(name, url) != null) return false;
    final now = _clock();
    final last = _lastSent[name];
    if (!force && last != null && now.difference(last) < const Duration(seconds: 5)) return false;
    _lastSent[name] = now;
    try {
      final req = await _client.postUrl(Uri.parse(url.trim())).timeout(const Duration(seconds: 6));
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode(payload(event, name: name, title: title, artist: artist, mood: mood, at: now))));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      final ok = res.statusCode < 300;
      lastResult[name] = ok ? 'Enviado (${res.statusCode})' : 'Tu servicio respondió ${res.statusCode}';
      notifyListeners();
      return ok;
    } catch (_) {
      lastResult[name] = 'No se pudo conectar';
      notifyListeners();
      return false;
    }
  }
}
