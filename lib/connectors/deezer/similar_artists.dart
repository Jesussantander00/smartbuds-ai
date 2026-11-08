import 'dart:convert';
import 'dart:io';

/// Un artista parecido y sus canciones más escuchadas.
class SimilarArtist {
  const SimilarArtist(this.name, this.topTracks);
  final String name;
  final List<String> topTracks;
}

/// Busca artistas parecidos a uno dado.
abstract class SimilarArtistsFinder {
  Future<List<SimilarArtist>> similarTo(String artist, {int max = 6});
}

/// Artistas parecidos con la API pública de Deezer (gratis, sin clave).
/// Solo se usan los nombres para buscar la canción en tu reproductor; no se
/// reproduce nada de Deezer.
class DeezerSimilarArtists implements SimilarArtistsFinder {
  DeezerSimilarArtists({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  static const _base = 'https://api.deezer.com';

  @override
  Future<List<SimilarArtist>> similarTo(String artist, {int max = 6}) async {
    final found = await _get('/search/artist?q=${Uri.encodeQueryComponent(artist)}&limit=1');
    final id = (found['data'] as List?)?.cast<Map>().firstOrNull?['id'];
    if (id == null) return const [];
    final related = await _get('/artist/$id/related?limit=$max');
    final out = <SimilarArtist>[];
    for (final a in ((related['data'] as List?) ?? const []).whereType<Map>()) {
      final name = a['name'] as String?;
      final aid = a['id'];
      if (name == null || aid == null) continue;
      final top = await _get('/artist/$aid/top?limit=5');
      final titles = [
        for (final t in ((top['data'] as List?) ?? const []).whereType<Map>())
          if (t['title'] is String) t['title'] as String,
      ];
      out.add(SimilarArtist(name, titles));
      if (out.length >= max) break;
    }
    return out;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final req =
        await _client.getUrl(Uri.parse('$_base$path')).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) return const {};
    final json = jsonDecode(text);
    return json is Map<String, dynamic> ? json : const {};
  }
}
