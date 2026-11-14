import 'dart:convert';
import 'dart:io';

import '../../connectors/youtube/youtube_search.dart';
import '../../core/voice_engine/command_parser.dart';

/// De dónde sale el audio que suena DENTRO de SmartBuds.
enum InAppSource {
  /// Reproductor oficial de YouTube incrustado (IFrame). Canción completa; el
  /// video debe verse (mínimo 200×200) y se pausa si sales de la app.
  youtube,

  /// Audius: catálogo abierto con API pública que permite reproducir en apps
  /// de terceros. Canciones completas, sobre todo artistas independientes.
  audius,

  /// Deezer: vista previa oficial de 30 segundos (la canción completa no se
  /// puede reproducir fuera de la app de Deezer).
  deezerPreview,
}

/// Una canción que SmartBuds puede reproducir por sí mismo.
class InAppTrack {
  const InAppTrack({
    required this.id,
    required this.source,
    required this.title,
    this.artist,
    this.artwork,
    this.durationMs,
    this.streamUrl,
    this.videoId,
  });

  final String id;
  final InAppSource source;
  final String title;
  final String? artist;
  final String? artwork;
  final int? durationMs;

  /// Audius / Deezer: dirección del audio.
  final String? streamUrl;

  /// YouTube: identificador del video.
  final String? videoId;

  bool get isPreview => source == InAppSource.deezerPreview;

  /// Etiqueta honesta para la pantalla.
  String get sourceLabel => switch (source) {
        InAppSource.youtube => 'Completa · YouTube',
        InAppSource.audius => 'Completa · Audius',
        InAppSource.deezerPreview => 'Vista previa 30 s · Deezer',
      };

  String get display => artist == null || artist!.isEmpty ? title : '$title — $artist';
}

/// Una fuente de canciones para el reproductor integrado.
abstract class InAppCatalog {
  InAppSource get source;
  Future<List<InAppTrack>> search(String query, {int max = 8});
}

/// YouTube: búsqueda con la API oficial (requiere tu clave, que no está en el
/// código) y reproducción con el reproductor oficial incrustado.
class YouTubeCatalog implements InAppCatalog {
  YouTubeCatalog(this.finder);
  final SongFinder finder;

  @override
  InAppSource get source => InAppSource.youtube;

  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    final hits = await finder.findMany(query, max: max);
    return [
      for (final h in hits)
        InAppTrack(
          id: 'yt:${h.videoId}',
          source: InAppSource.youtube,
          title: h.title,
          artist: h.channel,
          artwork: 'https://i.ytimg.com/vi/${h.videoId}/hqdefault.jpg',
          videoId: h.videoId,
        ),
    ];
  }
}

Future<Object?> _getJson(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
  final res = await req.close().timeout(const Duration(seconds: 8));
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) return null;
  return jsonDecode(body);
}

/// Audius (https://audius.org): API pública y gratuita; pide identificar la
/// app (`app_name`). Solo canciones marcadas como reproducibles.
class AudiusCatalog implements InAppCatalog {
  AudiusCatalog({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;
  static const appName = 'SmartBudsAI';
  String? _host;

  @override
  InAppSource get source => InAppSource.audius;

  Future<String?> _discover() async {
    if (_host != null) return _host;
    try {
      final d = await _getJson(_client, Uri.parse('https://api.audius.co'));
      final hosts = (d is Map ? d['data'] as List? : null)?.whereType<String>().toList() ?? const [];
      return _host = hosts.isEmpty ? null : hosts.first;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    final host = await _discover();
    if (host == null) return const [];
    try {
      final d = await _getJson(
          _client, Uri.parse('$host/v1/tracks/search?query=${Uri.encodeQueryComponent(query)}&app_name=$appName'));
      return parse(d, host, max: max);
    } catch (_) {
      return const [];
    }
  }

  static List<InAppTrack> parse(Object? json, String host, {int max = 8}) {
    final list = (json is Map ? json['data'] as List? : null)?.whereType<Map>() ?? const <Map>[];
    final out = <InAppTrack>[];
    for (final t in list) {
      final id = t['id'];
      final title = t['title'];
      if (id is! String || title is! String) continue;
      if (t['is_streamable'] == false || t['is_stream_gated'] == true) continue;
      final art = t['artwork'];
      out.add(InAppTrack(
        id: 'audius:$id',
        source: InAppSource.audius,
        title: title,
        artist: (t['user'] is Map) ? (t['user'] as Map)['name'] as String? : null,
        artwork: art is Map ? (art['480x480'] ?? art['150x150']) as String? : null,
        durationMs: (t['duration'] as num?) == null ? null : ((t['duration'] as num) * 1000).round(),
        streamUrl: '$host/v1/tracks/$id/stream?app_name=$appName',
      ));
      if (out.length >= max) break;
    }
    return out;
  }
}

/// Deezer: búsqueda pública (sin clave) con vista previa oficial de 30 s.
class DeezerPreviewCatalog implements InAppCatalog {
  DeezerPreviewCatalog({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  InAppSource get source => InAppSource.deezerPreview;

  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    try {
      final d = await _getJson(
          _client, Uri.parse('https://api.deezer.com/search?q=${Uri.encodeQueryComponent(query)}&limit=$max'));
      return parse(d, max: max);
    } catch (_) {
      return const [];
    }
  }

  static List<InAppTrack> parse(Object? json, {int max = 8}) {
    final list = (json is Map ? json['data'] as List? : null)?.whereType<Map>() ?? const <Map>[];
    final out = <InAppTrack>[];
    for (final t in list) {
      final preview = t['preview'];
      final title = t['title'];
      if (preview is! String || preview.isEmpty || title is! String) continue;
      out.add(InAppTrack(
        id: 'deezer:${t['id']}',
        source: InAppSource.deezerPreview,
        title: title,
        artist: (t['artist'] is Map) ? (t['artist'] as Map)['name'] as String? : null,
        artwork: (t['album'] is Map) ? (t['album'] as Map)['cover_medium'] as String? : null,
        durationMs: 30000,
        streamUrl: preview,
      ));
      if (out.length >= max) break;
    }
    return out;
  }
}

/// Junta las fuentes y decide qué suena: primero canciones completas que
/// coinciden con lo pedido; la vista previa de 30 s solo si no hay otra.
class MusicCatalog {
  MusicCatalog(this.catalogs);
  final List<InAppCatalog> catalogs;

  /// Todas las fuentes, en el orden de [catalogs].
  Future<List<InAppTrack>> search(String query, {int perSource = 6}) async {
    final results = await Future.wait([
      for (final c in catalogs) c.search(query, max: perSource).catchError((Object _) => const <InAppTrack>[]),
    ]);
    return [for (final r in results) ...r];
  }

  /// La mejor opción para reproducir ya.
  static InAppTrack? best(List<InAppTrack> results, String query) {
    if (results.isEmpty) return null;
    // YouTube ya ordena por relevancia; Audius solo si de verdad coincide.
    for (final r in results) {
      if (r.source == InAppSource.youtube) return r;
    }
    for (final r in results) {
      if (r.source == InAppSource.audius && matches(r, query)) return r;
    }
    for (final r in results) {
      if (r.source == InAppSource.deezerPreview) return r;
    }
    return results.first;
  }

  /// ¿El resultado se parece a lo pedido? (palabras en común del título o artista)
  static bool matches(InAppTrack t, String query) {
    final q = CommandParser.normalize(query).split(' ').where((w) => w.length > 2).toSet();
    if (q.isEmpty) return false;
    final have = CommandParser.normalize('${t.title} ${t.artist ?? ''}').split(' ').toSet();
    final common = q.intersection(have).length;
    return common >= (q.length >= 2 ? 2 : 1);
  }
}
