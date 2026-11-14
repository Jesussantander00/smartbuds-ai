import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';
import 'catalog.dart';

/// Fuentes musicales: qué permite de verdad cada plataforma y en qué orden
/// las usa el reproductor de SmartBuds.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, required this.settings, this.youtubeConfigured = false});
  final AppSettings settings;

  /// Hay clave de YouTube en esta instalación.
  final bool youtubeConfigured;

  static String _kind(PlaybackKind k) => switch (k) {
        PlaybackKind.full => 'Completa dentro de SmartBuds',
        PlaybackKind.preview => 'Solo vista previa (30 s)',
        PlaybackKind.externalOnly => 'No se puede reproducir dentro (solo en su app)',
      };

  void _move(int from, int to) {
    final names = [
      for (final n in settings.sourceOrder)
        if (InAppSource.values.any((s) => s.name == n)) n,
    ];
    final x = names.removeAt(from);
    names.insert(to, x);
    settings.setSourceOrder(names);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fuentes musicales')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final order = settings.sourceOrder;
          final sources = [
            for (final n in order) ...InAppSource.values.where((s) => s.name == n),
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Prioridad', style: theme.textTheme.titleMedium),
              Text(
                'Cuando una canción está en varias fuentes, suena la primera de esta lista. '
                'Las completas siempre van antes que las vistas previas.',
                style: theme.textTheme.bodySmall,
              ),
              Card(
                child: Column(
                  children: [
                    for (final (i, s) in sources.indexed)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(radius: 13, child: Text('${i + 1}')),
                        title: Text(ProviderRegistry.bySource(s).name),
                        subtitle: Text(
                          s == InAppSource.youtube && !youtubeConfigured
                              ? 'Sin clave de YouTube en esta instalación: no se usa'
                              : _kind(ProviderRegistry.bySource(s).playback),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Subir',
                              onPressed: i == 0 ? null : () => _move(i, i - 1),
                              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Bajar',
                              onPressed: i == sources.length - 1 ? null : () => _move(i, i + 1),
                              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Qué permite cada plataforma', style: theme.textTheme.titleMedium),
              Text('Buscar una canción no significa poder reproducirla. Esto es lo que de verdad se puede hoy.',
                  style: theme.textTheme.bodySmall),
              for (final p in ProviderRegistry.all)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(p.name, style: theme.textTheme.titleSmall)),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(p.integrated ? 'Integrado' : 'No integrado'),
                              backgroundColor: p.integrated ? Neon.cyan.withValues(alpha: .2) : null,
                            ),
                          ],
                        ),
                        Text(_kind(p.playback),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: p.playback == PlaybackKind.full
                                    ? Neon.cyan
                                    : p.playback == PlaybackKind.preview
                                        ? Colors.amber
                                        : theme.colorScheme.error)),
                        const SizedBox(height: 4),
                        Text('Buscar: ${p.search ? 'sí' : 'no'} · Álbumes y artistas: ${p.albumsArtists ? 'sí' : 'no'}',
                            style: theme.textTheme.bodySmall),
                        Text('Necesita: ${p.needs}', style: theme.textTheme.bodySmall),
                        Text('Android: ${p.android}', style: theme.textTheme.bodySmall),
                        Text('iPhone: ${p.ios}', style: theme.textTheme.bodySmall),
                        Text('Web: ${p.web}', style: theme.textTheme.bodySmall),
                        if (p.note.isNotEmpty) Text(p.note, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
