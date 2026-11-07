import 'dart:convert';
import 'dart:io';

/// Resultado de búsqueda en YouTube: lo necesario para abrir la canción exacta.
class YouTubeHit {
  const YouTubeHit({required this.videoId, required this.title, this.channel});
  final String videoId;
  final String title;
  final String? channel;
}

/// Busca canciones con la API oficial de YouTube (YouTube Data API v3).
/// Solo obtiene el identificador; la reproducción la hace YouTube Music.
///
/// La clave NO va en el código: se pasa al compilar con
///   flutter run --dart-define-from-file=secrets.json
/// (secrets.json está excluido de GitHub).
abstract class SongFinder {
  Future<YouTubeHit?> find(String query);

  /// Varios resultados (para «Pon algo nuevo»).
  Future<List<YouTubeHit>> findMany(String query, {int max = 10});
}

class YouTubeSearch implements SongFinder {
  YouTubeSearch({required this.apiKey, HttpClient? client})
      : _client = client ?? HttpClient();

  static const keyFromEnvironment = String.fromEnvironment('YOUTUBE_API_KEY');

  /// Null si no se configuró la clave.
  static YouTubeSearch? fromEnvironment() =>
      keyFromEnvironment.isEmpty ? null : YouTubeSearch(apiKey: keyFromEnvironment);

  final String apiKey;
  final HttpClient _client;

  @override
  Future<YouTubeHit?> find(String query) async {
    final hits = await findMany(query, max: 1);
    return hits.isEmpty ? null : hits.first;
  }

  @override
  Future<List<YouTubeHit>> findMany(String query, {int max = 10}) async {
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'videoCategoryId': '10', // Música
      'maxResults': '$max',
      'q': query,
      'key': apiKey,
    });
    try {
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return const [];
      return parseAll(body);
    } catch (_) {
      return const [];
    }
  }

  /// Público para probarlo sin red.
  static YouTubeHit? parse(String body) {
    final all = parseAll(body);
    return all.isEmpty ? null : all.first;
  }

  static List<YouTubeHit> parseAll(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final items = (json['items'] as List?) ?? const [];
    final hits = <YouTubeHit>[];
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final id = (m['id'] as Map?)?['videoId'] as String?;
      if (id == null) continue;
      final snippet = (m['snippet'] as Map?) ?? const {};
      hits.add(YouTubeHit(
        videoId: id,
        title: _unescape((snippet['title'] as String?) ?? ''),
        channel: snippet['channelTitle'] as String?,
      ));
    }
    return hits;
  }

  /// La API devuelve títulos con entidades HTML (&amp;, &#39;…).
  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
