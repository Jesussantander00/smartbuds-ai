import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connectors/knowledge/music_knowledge.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';

/// «Sobre el artista»: resumen con su fuente, datos de Deezer, artistas
/// parecidos y sus colaboraciones en tu música.
Future<void> showArtistInfo(BuildContext context, Assistant assistant, String artist) {
  final collabs = assistant.collaborationsOf(artist);
  final future = assistant.knowledge?.artist(artist) ?? Future<ArtistInfo?>.value(null);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .92,
        builder: (context, scroll) => FutureBuilder<ArtistInfo?>(
          future: future,
          builder: (context, snap) {
            final info = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: info?.picture == null ? null : NetworkImage(info!.picture!),
                      child: info?.picture == null ? const Icon(Icons.person, size: 32) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(artist, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          if (info?.fans != null || info?.albums != null)
                            Text(
                              [
                                if (info?.fans != null) '${_n(info!.fans!)} seguidores',
                                if (info?.albums != null) '${info!.albums} álbumes',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Pon algo de $artist',
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: () {
                        Navigator.pop(context);
                        assistant.handleSearch(SearchRequest(artist));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (loading)
                  const LinearProgressIndicator()
                else if (info?.summary != null) ...[
                  Text(info!.summary!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: info.sourceUrl ?? ''));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Enlace de Wikipedia copiado.')));
                      }
                    },
                    child: Text('Fuente: Wikipedia (toca para copiar el enlace)',
                        style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.underline)),
                  ),
                ] else
                  Text(
                    assistant.knowledge == null
                        ? 'Sin conexión para buscar información.'
                        : 'No encontré un artículo confiable sobre $artist. No invento datos.',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (collabs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Colaboraciones en tu música', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in collabs.take(12))
                        ActionChip(
                          avatar: const Icon(Icons.people_alt_rounded, size: 16),
                          label: Text(c),
                          onPressed: () {
                            Navigator.pop(context);
                            showArtistInfo(context, assistant, c);
                          },
                        ),
                    ],
                  ),
                ],
                if (info != null && info.related.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Si te gusta, prueba', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in info.related)
                        ActionChip(
                          avatar: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: Text(r),
                          onPressed: () {
                            Navigator.pop(context);
                            assistant.handleSearch(SearchRequest(r));
                          },
                        ),
                    ],
                  ),
                  Text('Datos de Deezer.', style: theme.textTheme.bodySmall),
                ],
              ],
            );
          },
        ),
      );
    },
  );
}

String _n(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)} M'
    : n >= 1000
        ? '${(n / 1000).round()} mil'
        : '$n';
