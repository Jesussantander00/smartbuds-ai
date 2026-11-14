import 'dart:convert';
import 'dart:io';

/// Un artista parecido y sus canciones más escuchadas.
class SimilarArtist {
  const SimilarArtist(this.name, this.topTracks, {this.fans, this.picture});
  final String name;
  final List<String> topTracks;

  /// Seguidores en Deezer (para el nivel de descubrimiento).
  final int? fans;
  final String? picture;
}

/// Busca artistas parecidos a uno dado.
abstract class SimilarArtistsFinder {
  Future<List<SimilarArtist>> similarTo(String artist, {int max = 6});

  /// Foto del artista (para las tarjetas de favoritos), o null.
  Future<String?> pictureOf(String artist) async => null;

  /// Con quién ha colaborado (artistas invitados en sus canciones más
  /// escuchadas) y en qué canción. Vacío si no se sabe.
  Future<List<Collaboration>> collaboratorsOf(String artist) async => const [];
}

/// Una colaboración real: [with_] aparece en la canción [song] de otro artista.
class Collaboration {
  const Collaboration(this.name, this.song, {this.fans});
  final String name;
  final String song;
  final int? fans;
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
      out.add(SimilarArtist(
        name,
        titles,
        fans: (a['nb_fan'] as num?)?.toInt(),
        picture: a['picture_medium'] as String?,
      ));
      if (out.length >= max) break;
    }
    return out;
  }

  /// Colaboradores: los «contributors» de sus 25 canciones más escuchadas en Deezer.
  @override
  Future<List<Collaboration>> collaboratorsOf(String artist) async {
    try {
      final found = await _get('/search/artist?q=${Uri.encodeQueryComponent(artist)}&limit=1');
      final first = (found['data'] as List?)?.whereType<Map>().firstOrNull;
      final id = first?['id'];
      if (id == null) return const [];
      final self = '${first?['name'] ?? artist}'.toLowerCase();
      final top = await _get('/artist/$id/top?limit=25');
      final out = <String, Collaboration>{};
      for (final t in ((top['data'] as List?) ?? const []).whereType<Map>()) {
        final title = t['title'];
        if (title is! String) continue;
        for (final c in ((t['contributors'] as List?) ?? const []).whereType<Map>()) {
          final name = c['name'];
          if (name is! String || name.toLowerCase() == self) continue;
          out.putIfAbsent(name.toLowerCase(), () => Collaboration(name, title));
        }
      }
      return out.values.toList();
    } catch (_) {
      return const [];
    }
  }

  final Map<String, String?> _pictures = {};

  @override
  Future<String?> pictureOf(String artist) async {
    if (_pictures.containsKey(artist)) return _pictures[artist];
    try {
      final found =
          await _get('/search/artist?q=${Uri.encodeQueryComponent(artist)}&limit=1');
      final pic = (found['data'] as List?)?.cast<Map>().firstOrNull?['picture_medium'];
      return _pictures[artist] = pic is String ? pic : null;
    } catch (_) {
      return null;
    }
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
