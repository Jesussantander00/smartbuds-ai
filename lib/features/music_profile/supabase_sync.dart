import 'dart:convert';
import 'dart:io';

import 'music_profile.dart';

/// Sincroniza el perfil musical con Supabase (opcional).
///
/// Se activa poniendo SUPABASE_URL y SUPABASE_ANON_KEY en secrets.json.
/// Las tablas se crean con supabase/schema.sql. Sin esas claves, el perfil
/// funciona igual, guardado solo en el teléfono.
class SupabaseSync {
  SupabaseSync({
    required this.url,
    required this.anonKey,
    required this.deviceId,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configured => _url.isNotEmpty && _key.isNotEmpty;

  static SupabaseSync? fromEnvironment(String deviceId) => configured
      ? SupabaseSync(url: _url, anonKey: _key, deviceId: deviceId)
      : null;

  final String url;
  final String anonKey;
  final String deviceId;
  final HttpClient _client;

  /// Último error (para mostrarlo en «Mi música»).
  String? lastError;
  DateTime? lastSyncAt;

  Future<void> push(ListenEvent event, TrackStats stats) async {
    try {
      await _post('listening_events', {
        'device_id': deviceId,
        'track_key': stats.key,
        'title': stats.title,
        'artist': stats.artist,
        'app_package': stats.packageName,
        'event_type': event.type.name,
        'happened_at': event.at.toUtc().toIso8601String(),
      });
      await _post(
        'track_scores?on_conflict=device_id,track_key',
        {
          'device_id': deviceId,
          'track_key': stats.key,
          'title': stats.title,
          'artist': stats.artist,
          'plays': stats.plays,
          'completes': stats.completes,
          'skips': stats.skips,
          'repeats': stats.repeats,
          'likes': stats.likes,
          'dislikes': stats.dislikes,
          'last_played_at': stats.lastPlayedAt?.toUtc().toIso8601String(),
        },
        upsert: true,
      );
      lastError = null;
      lastSyncAt = DateTime.now();
    } catch (e) {
      lastError = '$e';
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body, {bool upsert = false}) async {
    final req = await _client
        .postUrl(Uri.parse('$url/rest/v1/$path'))
        .timeout(const Duration(seconds: 8));
    req.headers.set('apikey', anonKey);
    // Las claves antiguas (anon) son JWT y también van en Authorization.
    // Las nuevas «publishable» (sb_publishable_…) solo van en apikey.
    if (anonKey.startsWith('eyJ')) {
      req.headers.set('Authorization', 'Bearer $anonKey');
    }
    req.headers
      ..set('Content-Type', 'application/json')
      ..set('Prefer',
          upsert ? 'resolution=merge-duplicates,return=minimal' : 'return=minimal');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 8));
    await res.drain<void>();
    if (res.statusCode >= 300) {
      throw HttpException('Supabase respondió ${res.statusCode} en $path');
    }
  }
}
