import 'dart:convert';
import 'dart:io';

/// Lo que se sabe de un artista, con su fuente (nada inventado por la IA).
class ArtistInfo {
  const ArtistInfo({
    required this.name,
    this.summary,
    this.sourceUrl,
    this.fans,
    this.albums,
    this.picture,
    this.related = const [],
  });

  final String name;

  /// Resumen de Wikipedia en español (si hay un artículo que sea de música).
  final String? summary;
  final String? sourceUrl;

  /// Datos de Deezer.
  final int? fans;
  final int? albums;
  final String? picture;
  final List<String> related;

  bool get isEmpty => summary == null && fans == null && related.isEmpty;

  /// Las primeras [n] oraciones del resumen (para decirlo en voz alta).
  String? shortSummary([int n = 2]) {
    final s = summary;
    if (s == null) return null;
    final parts = RegExp(r'[^.!?]+[.!?]+(\s|$)').allMatches(s).map((m) => m.group(0)!.trim()).toList();
    if (parts.isEmpty) return s;
    return parts.take(n).join(' ');
  }
}

/// Conocimiento musical con fuentes públicas y gratis, sin clave:
/// Wikipedia en español (resumen) y Deezer (seguidores, álbumes, parecidos).
/// Si Wikipedia no tiene un artículo que hable de música, no se usa (para no
/// confundir al artista con otra persona del mismo nombre).
class MusicKnowledge {
  MusicKnowledge({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, ArtistInfo?> _cache = {};

  static const _ua = 'SmartBudsAI/1.0 (https://github.com/Jesussantander00/smartbuds-ai)';

  /// Palabras que indican que el artículo es de un artista musical.
  static const _musicWords = [
    'cantante', 'músic', 'banda', 'rapero', 'rapera', 'compositor', 'compositora', 'grupo musical',
    'productor musical', 'productora musical', 'dj', 'disc jockey', 'cantautor', 'cantautora',
    'agrupación', 'orquesta', 'reguetón', 'reggaetón', 'trap', 'álbum', 'sencillo',
  ];

  /// ¿El texto describe a alguien de la música? (público para las pruebas)
  static bool looksMusical(String text) {
    final t = text.toLowerCase();
    return _musicWords.any((w) => RegExp('(^|[^a-záéíóúñ])${RegExp.escape(w)}').hasMatch(t));
  }

  Future<ArtistInfo?> artist(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    String? summary, url;
    int? fans, albums;
    String? picture;
    var related = <String>[];
    try {
      final search = await _json(Uri.https('es.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': '$name música',
        'srlimit': '3',
        'format': 'json',
      }));
      final hits = (((search['query'] as Map?)?['search'] as List?) ?? const []).whereType<Map>();
      for (final h in hits) {
        final title = h['title'] as String?;
        if (title == null) continue;
        final page = await _json(
            Uri.parse('https://es.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}'));
        final extract = page['extract'] as String?;
        if (page['type'] == 'disambiguation' || extract == null || !looksMusical(extract)) continue;
        summary = extract;
        url = ((page['content_urls'] as Map?)?['mobile'] as Map?)?['page'] as String? ??
            'https://es.wikipedia.org/wiki/${Uri.encodeComponent(title)}';
        break;
      }
    } catch (_) {}
    try {
      final found = await _json(Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeQueryComponent(name)}&limit=1'));
      final a = ((found['data'] as List?) ?? const []).whereType<Map>().firstOrNull;
      if (a != null) {
        fans = (a['nb_fan'] as num?)?.toInt();
        albums = (a['nb_album'] as num?)?.toInt();
        picture = a['picture_medium'] as String?;
        final rel = await _json(Uri.parse('https://api.deezer.com/artist/${a['id']}/related?limit=5'));
        related = [
          for (final r in ((rel['data'] as List?) ?? const []).whereType<Map>())
            if (r['name'] is String) r['name'] as String,
        ];
      }
    } catch (_) {}
    final info = ArtistInfo(
      name: name,
      summary: summary,
      sourceUrl: url,
      fans: fans,
      albums: albums,
      picture: picture,
      related: related,
    );
    return _cache[key] = info.isEmpty ? null : info;
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 6));
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 6));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) return const {};
    final j = jsonDecode(text);
    return j is Map<String, dynamic> ? j : const {};
  }
}

/// Colaboraciones que aparecen en TU música: «Feid ft. Karol G», «A, B & C»,
/// «Canción (feat. X)». Solo con tus canciones, sin buscar en internet.
List<String> collaborationsIn(Iterable<({String title, String? artist})> songs, String artist) {
  final target = artist.trim().toLowerCase();
  final counts = <String, int>{};
  final names = <String, String>{};
  final split = RegExp(r'\s*(?:,|&| y | x | ft\.? | feat\.? | featuring | con )\s*', caseSensitive: false);
  final feat = RegExp(r'[\(\[]?\s*(?:ft\.?|feat\.?|featuring|con)\s+([^\)\]]+)[\)\]]?', caseSensitive: false);
  for (final s in songs) {
    final people = <String>[];
    if (s.artist != null) people.addAll(s.artist!.split(split));
    final m = feat.firstMatch(s.title);
    if (m != null) people.addAll(m.group(1)!.split(split));
    final clean = [for (final p in people) p.trim()].where((p) => p.isNotEmpty).toList();
    if (!clean.any((p) => p.toLowerCase() == target)) continue;
    for (final p in clean) {
      final k = p.toLowerCase();
      if (k == target) continue;
      counts[k] = (counts[k] ?? 0) + 1;
      names[k] ??= p;
    }
  }
  final sorted = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (final k in sorted) names[k]!];
}
