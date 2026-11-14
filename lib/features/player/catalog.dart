import 'dart:convert';
import 'dart:io';

import '../../connectors/youtube/youtube_search.dart';
import '../../core/voice_engine/command_parser.dart';

// ============================================================================
// Centro musical: proveedores (adaptadores) → buscador unificado → reproductor
// central. Buscar NO es lo mismo que reproducir: cada proveedor declara qué
// permite (ver [ProviderInfo]) y solo se ofrece lo que de verdad funciona.
// ============================================================================

/// De dónde sale el audio que suena DENTRO de SmartBuds.
enum InAppSource {
  /// Reproductor oficial de YouTube incrustado (IFrame). Canción completa; el
  /// video debe verse (mínimo 200×200) y se pausa si sales de la app.
  youtube,

  /// Audius: API pública que permite reproducir en apps de terceros.
  /// Canciones completas, sobre todo artistas independientes.
  audius,

  /// Deezer: vista previa oficial de 30 segundos.
  deezerPreview,

  /// Apple (iTunes Search API): vista previa oficial de 30 segundos.
  itunesPreview,
}

/// Qué tipo de reproducción permite un proveedor dentro de SmartBuds.
enum PlaybackKind {
  /// Canción completa dentro de SmartBuds.
  full,

  /// Solo un fragmento (≈30 s).
  preview,

  /// Solo se puede escuchar en la app del proveedor (no se ofrece como reproducible).
  externalOnly,
}

/// Capacidades REALES de un proveedor (auditadas, ver docs/centro-musical.md).
class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.search,
    required this.albumsArtists,
    required this.playback,
    required this.needs,
    required this.android,
    required this.ios,
    required this.web,
    required this.integrated,
    this.source,
    this.note = '',
  });

  final String id;
  final String name;

  /// Permite buscar canciones / consultar álbumes y artistas (con portadas).
  final bool search;
  final bool albumsArtists;
  final PlaybackKind playback;

  /// Cuenta, suscripción o autorización que exige.
  final String needs;

  /// Qué funciona en cada plataforma (texto honesto).
  final String android, ios, web;

  /// SmartBuds ya lo usa en el buscador y el reproductor.
  final bool integrated;
  final InAppSource? source;
  final String note;
}

/// Auditoría de proveedores (noviembre 2026).
class ProviderRegistry {
  static const all = <ProviderInfo>[
    ProviderInfo(
      id: 'youtube',
      name: 'YouTube',
      search: true,
      albumsArtists: false,
      playback: PlaybackKind.full,
      needs: 'Clave de YouTube Data API (de quien instala la app). El usuario no necesita cuenta.',
      android: 'Completa con el reproductor oficial incrustado; se pausa en segundo plano.',
      ios: 'Completa con el reproductor oficial incrustado; se pausa en segundo plano.',
      web: 'Completa en la página («Aquí mismo»).',
      integrated: true,
      source: InAppSource.youtube,
      note: 'El video debe verse (mín. 200×200). Algunos videos no se dejan incrustar. '
          'YouTube Music no tiene API pública propia: se usa el catálogo de YouTube.',
    ),
    ProviderInfo(
      id: 'audius',
      name: 'Audius',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.full,
      needs: 'Nada (API pública, se identifica la app).',
      android: 'Completa; sigue con la pantalla apagada.',
      ios: 'Completa; sigue con la pantalla apagada.',
      web: 'No integrado en la página todavía.',
      integrated: true,
      source: InAppSource.audius,
      note: 'Catálogo de artistas independientes: casi nunca tiene éxitos comerciales.',
    ),
    ProviderInfo(
      id: 'deezer',
      name: 'Deezer',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.preview,
      needs: 'Nada para buscar y la vista previa.',
      android: 'Vista previa de 30 s.',
      ios: 'Vista previa de 30 s.',
      web: 'No integrado en la página (su API no permite llamadas desde el navegador).',
      integrated: true,
      source: InAppSource.deezerPreview,
      note: 'La canción completa solo en la app de Deezer (su SDK para terceros ya no se ofrece).',
    ),
    ProviderInfo(
      id: 'itunes',
      name: 'Apple (iTunes Search)',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.preview,
      needs: 'Nada para buscar y la vista previa.',
      android: 'Vista previa de 30 s.',
      ios: 'Vista previa de 30 s.',
      web: 'No integrado en la página.',
      integrated: true,
      source: InAppSource.itunesPreview,
      note: 'Catálogo de Apple con portadas y álbumes. Vista previa oficial.',
    ),
    ProviderInfo(
      id: 'applemusic',
      name: 'Apple Music (MusicKit)',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.externalOnly,
      needs: 'Cuenta de desarrollador de Apple (de pago), permiso de MusicKit y suscripción del usuario.',
      android: 'Existe un SDK de MusicKit para Android, pero exige lo mismo.',
      ios: 'ApplicationMusicPlayer reproduce completo dentro con suscripción, cuando haya cuenta de desarrollador.',
      web: 'MusicKit JS, con suscripción.',
      integrated: false,
      note: 'Posible a futuro; hoy no hay cuenta de desarrollador. Sin suscripción solo hay vistas previas.',
    ),
    ProviderInfo(
      id: 'spotify',
      name: 'Spotify',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.externalOnly,
      needs: 'App registrada en Spotify y autorización del usuario. Reproducir: Premium.',
      android: 'App Remote solo controla la app de Spotify (el audio sale de Spotify, no de SmartBuds).',
      ios: 'App Remote solo controla la app de Spotify.',
      web: 'Web Playback SDK: solo navegador y solo Premium.',
      integrated: false,
      note: 'Desde nov. 2024 las apps nuevas no reciben vistas previas de 30 s. No se finge reproducción.',
    ),
    ProviderInfo(
      id: 'soundcloud',
      name: 'SoundCloud',
      search: true,
      albumsArtists: true,
      playback: PlaybackKind.externalOnly,
      needs: 'App registrada (el registro puede estar cerrado) y un servidor propio que guarde la clave secreta.',
      android: 'Posible con API oficial + servidor; no disponible hoy.',
      ios: 'Posible con API oficial + servidor; no disponible hoy.',
      web: 'Su reproductor incrustado oficial sería posible en la página.',
      integrated: false,
      note: 'La clave secreta no puede ir dentro de la app. Se integrará cuando haya credenciales y servidor.',
    ),
  ];

  static ProviderInfo bySource(InAppSource s) => all.firstWhere((p) => p.source == s);
}

/// Una forma concreta de hacer sonar una canción dentro de SmartBuds.
class InAppTrack {
  const InAppTrack({
    required this.id,
    required this.source,
    required this.title,
    this.artist,
    this.album,
    this.artwork,
    this.durationMs,
    this.streamUrl,
    this.videoId,
  });

  final String id;
  final InAppSource source;
  final String title;
  final String? artist;
  final String? album;
  final String? artwork;
  final int? durationMs;

  /// Audius / Deezer / Apple: dirección del audio.
  final String? streamUrl;

  /// YouTube: identificador del video.
  final String? videoId;

  bool get isPreview => source == InAppSource.deezerPreview || source == InAppSource.itunesPreview;
  PlaybackKind get playback => isPreview ? PlaybackKind.preview : PlaybackKind.full;

  /// Etiqueta honesta para la pantalla.
  String get sourceLabel => switch (source) {
        InAppSource.youtube => 'Completa · YouTube',
        InAppSource.audius => 'Completa · Audius',
        InAppSource.deezerPreview => 'Vista previa 30 s · Deezer',
        InAppSource.itunesPreview => 'Vista previa 30 s · Apple',
      };

  String get display => artist == null || artist!.isEmpty ? title : '$title — $artist';
}

/// Un álbum encontrado.
class AlbumHit {
  const AlbumHit({required this.id, required this.title, this.artist, this.artwork, this.year, required this.provider});
  final String id;
  final String title;
  final String? artist;
  final String? artwork;
  final String? year;
  final String provider;
}

/// Adaptador de un proveedor: busca y entrega formas de reproducir.
abstract class InAppCatalog {
  InAppSource get source;
  ProviderInfo get info => ProviderRegistry.bySource(source);
  Future<List<InAppTrack>> search(String query, {int max = 8});
  Future<List<AlbumHit>> albums(String query, {int max = 6}) async => const [];
  Future<List<InAppTrack>> albumTracks(AlbumHit album) async => const [];
}

Future<Object?> _getJson(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
  final res = await req.close().timeout(const Duration(seconds: 8));
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) return null;
  return jsonDecode(body);
}

/// YouTube: búsqueda con la API oficial y reproductor oficial incrustado.
class YouTubeCatalog extends InAppCatalog {
  YouTubeCatalog(this.finder);
  final SongFinder finder;

  @override
  InAppSource get source => InAppSource.youtube;

  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    final hits = await finder.findMany(query, max: max);
    return [
      for (final h in hits)
        () {
          final (title, artist) = MusicCatalog.splitYouTube(h.title, h.channel);
          return InAppTrack(
            id: 'yt:${h.videoId}',
            source: InAppSource.youtube,
            title: title,
            artist: artist,
            artwork: 'https://i.ytimg.com/vi/${h.videoId}/hqdefault.jpg',
            videoId: h.videoId,
          );
        }(),
    ];
  }
}

/// Audius (https://audius.org): API pública; pide identificar la app.
class AudiusCatalog extends InAppCatalog {
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

/// Deezer: búsqueda pública (sin clave), álbumes y vista previa oficial de 30 s.
class DeezerPreviewCatalog extends InAppCatalog {
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

  @override
  Future<List<AlbumHit>> albums(String query, {int max = 6}) async {
    try {
      final d = await _getJson(
          _client, Uri.parse('https://api.deezer.com/search/album?q=${Uri.encodeQueryComponent(query)}&limit=$max'));
      return parseAlbums(d);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<InAppTrack>> albumTracks(AlbumHit album) async {
    if (album.provider != 'deezer' || !RegExp(r'^\d+$').hasMatch(album.id)) return const [];
    try {
      final d = await _getJson(_client, Uri.parse('https://api.deezer.com/album/${album.id}/tracks?limit=50'));
      return parse(d, max: 50, album: album.title, artwork: album.artwork, fallbackArtist: album.artist);
    } catch (_) {
      return const [];
    }
  }

  static List<InAppTrack> parse(Object? json, {int max = 8, String? album, String? artwork, String? fallbackArtist}) {
    final list = (json is Map ? json['data'] as List? : null)?.whereType<Map>() ?? const <Map>[];
    final out = <InAppTrack>[];
    for (final t in list) {
      final preview = t['preview'];
      final title = t['title'];
      if (preview is! String || preview.isEmpty || title is! String) continue;
      final alb = t['album'] is Map ? t['album'] as Map : null;
      out.add(InAppTrack(
        id: 'deezer:${t['id']}',
        source: InAppSource.deezerPreview,
        title: title,
        artist: (t['artist'] is Map) ? (t['artist'] as Map)['name'] as String? : fallbackArtist,
        album: (alb?['title'] as String?) ?? album,
        artwork: (alb?['cover_medium'] as String?) ?? artwork,
        durationMs: (t['duration'] as num?) == null ? null : ((t['duration'] as num) * 1000).round(),
        streamUrl: preview,
      ));
      if (out.length >= max) break;
    }
    return out;
  }

  static List<AlbumHit> parseAlbums(Object? json) {
    final list = (json is Map ? json['data'] as List? : null)?.whereType<Map>() ?? const <Map>[];
    return [
      for (final a in list)
        if (a['id'] != null && a['title'] is String)
          AlbumHit(
            id: '${a['id']}',
            title: a['title'] as String,
            artist: (a['artist'] is Map) ? (a['artist'] as Map)['name'] as String? : null,
            artwork: a['cover_medium'] as String?,
            provider: 'deezer',
          ),
    ];
  }
}

/// Apple (iTunes Search API): búsqueda pública, portadas, álbumes y vista
/// previa oficial de 30 s. La canción completa de Apple Music exige MusicKit.
class ITunesCatalog extends InAppCatalog {
  ITunesCatalog({HttpClient? client, this.country = 'CO'}) : _client = client ?? HttpClient();
  final HttpClient _client;
  final String country;

  @override
  InAppSource get source => InAppSource.itunesPreview;

  @override
  Future<List<InAppTrack>> search(String query, {int max = 8}) async {
    try {
      final d = await _getJson(
          _client,
          Uri.https('itunes.apple.com', '/search',
              {'term': query, 'media': 'music', 'entity': 'song', 'limit': '$max', 'country': country}));
      return parse(d, max: max);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<AlbumHit>> albums(String query, {int max = 6}) async {
    try {
      final d = await _getJson(
          _client,
          Uri.https('itunes.apple.com', '/search',
              {'term': query, 'media': 'music', 'entity': 'album', 'limit': '$max', 'country': country}));
      final list = (d is Map ? d['results'] as List? : null)?.whereType<Map>() ?? const <Map>[];
      return [
        for (final a in list)
          if (a['collectionId'] != null && a['collectionName'] is String)
            AlbumHit(
              id: '${a['collectionId']}',
              title: a['collectionName'] as String,
              artist: a['artistName'] as String?,
              artwork: a['artworkUrl100'] as String?,
              year: (a['releaseDate'] as String?)?.substring(0, 4),
              provider: 'itunes',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<InAppTrack> parse(Object? json, {int max = 8}) {
    final list = (json is Map ? json['results'] as List? : null)?.whereType<Map>() ?? const <Map>[];
    final out = <InAppTrack>[];
    for (final t in list) {
      final preview = t['previewUrl'];
      final title = t['trackName'];
      if (preview is! String || !preview.startsWith('https://') || title is! String) continue;
      out.add(InAppTrack(
        id: 'itunes:${t['trackId']}',
        source: InAppSource.itunesPreview,
        title: title,
        artist: t['artistName'] as String?,
        album: t['collectionName'] as String?,
        artwork: (t['artworkUrl100'] as String?)?.replaceFirst('100x100', '300x300'),
        durationMs: (t['trackTimeMillis'] as num?)?.toInt(),
        streamUrl: preview,
      ));
      if (out.length >= max) break;
    }
    return out;
  }
}

/// Una canción en el buscador unificado: una sola fila aunque esté en varios
/// proveedores; [options] son las formas de reproducirla, de la mejor a la peor.
class MusicResult {
  MusicResult(this.key, this.options);
  final String key;
  final List<InAppTrack> options;

  /// Coincide con lo buscado (para ordenar).
  bool matches = false;
  int firstSeen = 0;

  InAppTrack get best => options.first;
  String get title => best.title;
  String? get artist => options.map((o) => o.artist).firstWhere((a) => a != null && a.isNotEmpty, orElse: () => null);
  String? get album => options.map((o) => o.album).firstWhere((a) => a != null, orElse: () => null);
  String? get artwork => options
      .map((o) => o.artwork)
      .firstWhere((a) => a != null, orElse: () => null);
  int? get durationMs =>
      options.where((o) => !o.isPreview).map((o) => o.durationMs).firstWhere((d) => d != null, orElse: () => null);
  bool get hasFull => options.any((o) => !o.isPreview);
  PlaybackKind get playback => hasFull ? PlaybackKind.full : PlaybackKind.preview;

  /// Estado de disponibilidad, en palabras.
  String get availability => hasFull ? 'Completa en SmartBuds' : 'Solo vista previa de 30 s en SmartBuds';
  String get display => artist == null ? title : '$title — $artist';
}

/// Buscador musical unificado: consulta los proveedores integrados, une los
/// resultados, quita duplicados y prioriza la reproducción completa.
class MusicCatalog {
  MusicCatalog(this.catalogs, {List<InAppSource> Function()? order}) : _order = order;
  final List<InAppCatalog> catalogs;
  final List<InAppSource> Function()? _order;

  /// Prioridad de fuentes (configurable). Las completas siempre antes que las vistas previas.
  List<InAppSource> get order => _order?.call() ?? InAppSource.values;

  Future<List<MusicResult>> search(String query, {int perSource = 6}) async {
    final results = await Future.wait([
      for (final c in catalogs) c.search(query, max: perSource).catchError((Object _) => const <InAppTrack>[]),
    ]);
    // Intercalar: la relevancia de cada proveedor se respeta.
    final all = <InAppTrack>[];
    for (var i = 0; i < perSource; i++) {
      for (final r in results) {
        if (i < r.length) all.add(r[i]);
      }
    }
    return merge(all, query, order);
  }

  Future<List<AlbumHit>> albums(String query) async {
    final results = await Future.wait([
      for (final c in catalogs) c.albums(query).catchError((Object _) => const <AlbumHit>[]),
    ]);
    final seen = <String>{};
    return [
      for (final r in results)
        for (final a in r)
          if (seen.add('${CommandParser.normalize(a.title)}|${CommandParser.normalize(a.artist ?? '')}')) a,
    ];
  }

  Future<List<InAppTrack>> albumTracks(AlbumHit album) async {
    for (final c in catalogs) {
      final t = await c.albumTracks(album).catchError((Object _) => const <InAppTrack>[]);
      if (t.isNotEmpty) return t;
    }
    return const [];
  }

  /// Une resultados de varios proveedores en filas sin duplicados.
  static List<MusicResult> merge(List<InAppTrack> all, String query, List<InAppSource> order) {
    final byKey = <String, MusicResult>{};
    var i = 0;
    for (final t in all) {
      final k = keyOf(t.title, t.artist);
      final r = byKey.putIfAbsent(k, () => MusicResult(k, [])..firstSeen = i);
      if (!r.options.any((o) => o.source == t.source)) r.options.add(t);
      i++;
    }
    int rank(InAppTrack t) {
      final i = order.indexOf(t.source);
      return (t.isPreview ? 100 : 0) + (i < 0 ? 50 : i);
    }
    final out = byKey.values.toList();
    for (final r in out) {
      r.options.sort((a, b) => rank(a).compareTo(rank(b)));
      r.matches = r.options.any((o) => matches(o, query));
    }
    // Audius suelto que no tiene nada que ver con lo pedido: fuera (no se finge).
    out.removeWhere((r) => !r.matches && r.options.every((o) => o.source == InAppSource.audius));
    out.sort((a, b) {
      if (a.matches != b.matches) return a.matches ? -1 : 1;
      if (a.hasFull != b.hasFull) return a.hasFull ? -1 : 1;
      return a.firstSeen.compareTo(b.firstSeen);
    });
    return out;
  }

  /// Clave para quitar duplicados: título sin «(Video oficial)», «feat.»… + artista principal.
  static String keyOf(String title, String? artist) {
    var t = title.toLowerCase();
    t = t.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' '); // (Official Video), [Letra]…
    t = t.replaceAll(RegExp(r'\s(feat|ft|with)\.?\s.*$'), ' ');
    var a = (artist ?? '').toLowerCase();
    a = a.replaceAll(RegExp(r'\s*-\s*topic$'), '').replaceAll(RegExp(r'vevo$'), '');
    a = a.split(RegExp(r',|&| x | y | feat\.? | ft\.? ')).first;
    return '${CommandParser.normalize(t)}|${CommandParser.normalize(a)}';
  }

  /// «Artista - Canción (Official Video)» de YouTube → (canción, artista).
  static (String, String?) splitYouTube(String title, String? channel) {
    final ch = channel?.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '').trim();
    final clean = title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*(official|oficial|video|audio|lyric|letra|visualizer|hd|4k)[^\)\]]*[\)\]]', caseSensitive: false), '').trim();
    final dash = clean.indexOf(' - ');
    if (dash > 0) return (clean.substring(dash + 3).trim(), clean.substring(0, dash).trim());
    return (clean, ch);
  }

  /// ¿El resultado se parece a lo pedido? (palabras en común del título o artista)
  static bool matches(InAppTrack t, String query) {
    final q = CommandParser.normalize(query)
        .split(' ')
        .where((w) => w.length > 2 && !const {'musica', 'cancion', 'canciones', 'que', 'una', 'del', 'los', 'las'}.contains(w))
        .toSet();
    if (q.isEmpty) return false;
    final have = CommandParser.normalize('${t.title} ${t.artist ?? ''} ${t.album ?? ''}').split(' ').toSet();
    final common = q.intersection(have).length;
    return common >= (q.length >= 2 ? 2 : 1) || (q.length >= 3 && common >= q.length - 1);
  }
}
