import 'dart:convert';
import 'dart:io';

import '../account/supabase_auth.dart';
import 'music_profile.dart';

/// Sincroniza el perfil musical con Supabase (opcional).
///
/// Se activa poniendo SUPABASE_URL y SUPABASE_ANON_KEY en secrets.json.
/// Las tablas se crean con supabase/schema.sql. Sin esas claves, el perfil
/// funciona igual, guardado solo en el teléfono.
///
/// Sin cuenta, los datos van con un identificador anónimo del teléfono.
/// Con cuenta ([auth]), van a nombre del usuario y solo él puede leerlos, así
/// sus gustos lo siguen a otro teléfono o al reinstalar la app.
class SupabaseSync {
  SupabaseSync({
    required this.url,
    required this.anonKey,
    required this.deviceId,
    this.auth,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  static const envUrl = String.fromEnvironment('SUPABASE_URL');
  static const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configured => envUrl.isNotEmpty && envKey.isNotEmpty;

  static SupabaseSync? fromEnvironment(String deviceId, {SupabaseAuth? auth}) =>
      configured
          ? SupabaseSync(url: envUrl, anonKey: envKey, deviceId: deviceId, auth: auth)
          : null;

  final String url;
  final String anonKey;
  final String deviceId;
  final SupabaseAuth? auth;
  final HttpClient _client;

  /// Último error (para mostrarlo en «Mi música»).
  String? lastError;
  DateTime? lastSyncAt;

  Future<void> push(ListenEvent event, TrackStats stats) async {
    try {
      final who = await _identity();
      await _send('POST', 'listening_events', who.token, {
        ...who.fields,
        'track_key': stats.key,
        'title': stats.title,
        'artist': stats.artist,
        'app_package': stats.packageName,
        'event_type': event.type.name,
        'happened_at': event.at.toUtc().toIso8601String(),
      });
      await _pushScore(who, stats);
      lastError = null;
      lastSyncAt = DateTime.now();
    } catch (e) {
      lastError = '$e';
    }
  }

  /// Trae las canciones guardadas en la cuenta (solo con sesión iniciada).
  Future<List<TrackStats>> pullScores() async {
    final who = await _identity();
    if (!who.signedIn) return const [];
    final id = Uri.encodeQueryComponent(who.fields['device_id'] as String);
    final text = await _send(
        'GET', 'track_scores?select=*&device_id=eq.$id&limit=2000', who.token, null);
    final rows = jsonDecode(text);
    if (rows is! List) return const [];
    return [
      for (final r in rows.whereType<Map>())
        TrackStats(
          key: '${r['track_key']}',
          title: '${r['title']}',
          artist: r['artist'] as String?,
          plays: (r['plays'] as num?)?.toInt() ?? 0,
          completes: (r['completes'] as num?)?.toInt() ?? 0,
          skips: (r['skips'] as num?)?.toInt() ?? 0,
          repeats: (r['repeats'] as num?)?.toInt() ?? 0,
          likes: (r['likes'] as num?)?.toInt() ?? 0,
          dislikes: (r['dislikes'] as num?)?.toInt() ?? 0,
          lastPlayedAt: DateTime.tryParse('${r['last_played_at']}')?.toLocal(),
        ),
    ];
  }

  /// Sube las puntuaciones de todo el perfil (al entrar a la cuenta).
  Future<void> pushAll(MusicProfile profile) async {
    try {
      final who = await _identity();
      for (final t in profile.tracks.values.toList()) {
        await _pushScore(who, t);
      }
      lastError = null;
      lastSyncAt = DateTime.now();
    } catch (e) {
      lastError = '$e';
    }
  }

  Future<void> _pushScore(_Identity who, TrackStats stats) => _send(
        'POST',
        'track_scores?on_conflict=device_id,track_key',
        who.token,
        {
          ...who.fields,
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

  Future<_Identity> _identity() async {
    final a = auth;
    if (a != null && a.signedIn) {
      final token = await a.validToken();
      final uid = a.userId;
      if (token != null && uid != null) {
        // Un solo «dispositivo» por cuenta: todos tus teléfonos suman juntos.
        return _Identity(token, {'device_id': 'u:$uid', 'user_id': uid}, signedIn: true);
      }
    }
    return _Identity(null, {'device_id': deviceId});
  }

  Future<String> _send(String method, String path, String? token, Map<String, dynamic>? body,
      {bool upsert = false}) async {
    final req = await _client
        .openUrl(method, Uri.parse('$url/rest/v1/$path'))
        .timeout(const Duration(seconds: 8));
    req.headers.set('apikey', anonKey);
    // Con cuenta: el token del usuario. Sin cuenta: la clave pública si es
    // de las antiguas (JWT); las nuevas «publishable» solo van en apikey.
    final bearer = token ?? (anonKey.startsWith('eyJ') ? anonKey : null);
    if (bearer != null) req.headers.set('Authorization', 'Bearer $bearer');
    if (body != null) {
      req.headers
        ..set('Content-Type', 'application/json')
        ..set('Prefer',
            upsert ? 'resolution=merge-duplicates,return=minimal' : 'return=minimal');
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw HttpException('Supabase respondió ${res.statusCode} en ${path.split('?').first}');
    }
    return text;
  }
}

class _Identity {
  _Identity(this.token, this.fields, {this.signedIn = false});
  final String? token;
  final Map<String, dynamic> fields;
  final bool signedIn;
}
