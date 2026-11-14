@Tags(['en-vivo'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbuds_ai/features/player/catalog.dart';

/// Pruebas contra los servicios REALES (no simulados): que cada proveedor
/// responda, que lo que SmartBuds entiende de su respuesta sea correcto y que
/// el audio que se ofrece como reproducible de verdad se pueda descargar.
/// No usan TestWidgetsFlutterBinding (para que el cliente HTTP sea el real).
void main() {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  /// Pide los primeros bytes del audio: ¿responde y es audio?
  Future<(int, String)> probe(String url) async {
    final req = await http.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=0-2047');
    final res = await req.close();
    await res.drain<void>();
    return (res.statusCode, res.headers.contentType?.mimeType ?? '');
  }

  test('Deezer: búsqueda real con vista previa reproducible', () async {
    final r = await DeezerPreviewCatalog().search("Shakira Hips Don't Lie");
    expect(r, isNotEmpty);
    final t = r.first;
    expect(t.artist?.toLowerCase(), contains('shakira'));
    expect(t.album, isNotNull);
    expect(t.artwork, startsWith('https://'));
    final (code, mime) = await probe(t.streamUrl!);
    expect(code, anyOf(200, 206), reason: t.streamUrl);
    expect(mime, startsWith('audio/'), reason: mime);
  });

  test('Deezer: álbum real y sus canciones', () async {
    final albums = await DeezerPreviewCatalog().albums('Pies Descalzos Shakira');
    expect(albums, isNotEmpty);
    final tracks = await DeezerPreviewCatalog().albumTracks(albums.first);
    expect(tracks.length, greaterThan(3));
  });

  test('Apple (iTunes): búsqueda real con vista previa reproducible', () async {
    final r = await ITunesCatalog().search('Shakira');
    expect(r, isNotEmpty);
    expect(r.first.album, isNotNull);
    final (code, mime) = await probe(r.first.streamUrl!);
    expect(code, anyOf(200, 206), reason: r.first.streamUrl);
    expect(mime, startsWith('audio/'), reason: mime);
    expect(await ITunesCatalog().albums('Pies Descalzos'), isNotEmpty);
  });

  test('Audius: búsqueda real con canción completa reproducible', () async {
    final r = await AudiusCatalog().search('lofi');
    expect(r, isNotEmpty);
    final t = r.first;
    expect(t.isPreview, isFalse);
    expect(t.durationMs, greaterThan(60000), reason: 'canción completa, no fragmento');
    final (code, _) = await probe(t.streamUrl!);
    expect(code, anyOf(200, 206), reason: t.streamUrl);
  });

  test('Buscador unificado real: «Shakira» sin duplicados y con fuentes correctas', () async {
    final c = MusicCatalog([AudiusCatalog(), DeezerPreviewCatalog(), ITunesCatalog()]);
    final r = await c.search('Shakira');
    expect(r, isNotEmpty);
    final keys = r.map((x) => x.key).toList();
    expect(keys.toSet().length, keys.length, reason: 'sin filas duplicadas');
    // Deezer y Apple tienen la misma canción: deben quedar unidas en una fila.
    expect(r.any((x) => x.options.length >= 2), isTrue, reason: r.map((x) => x.display).join(' | '));
    for (final x in r) {
      expect(x.options.first.isPreview, !x.hasFull, reason: 'la completa va primero: ${x.display}');
    }
    // Ninguna de estas fuentes es Spotify/Apple Music/SoundCloud (no integrables).
    expect(r.expand((x) => x.options).map((o) => o.source).toSet(),
        everyElement(isIn([InAppSource.audius, InAppSource.deezerPreview, InAppSource.itunesPreview])));
  });
}
