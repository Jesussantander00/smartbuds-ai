import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'connections.dart';

/// Descubrir por conexiones: artistas nuevos que colaboraron con los tuyos o
/// comparten su estilo.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, required this.assistant, this.around});
  final Assistant assistant;

  /// Solo alrededor de este artista (o null: tus artistas principales).
  final String? around;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Future<List<ArtistDiscovery>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.assistant.discoverConnections(around: widget.around);
  }

  void _refresh() => setState(() {
        _future = widget.assistant.discoverConnections(around: widget.around, refresh: true);
      });

  static (IconData, String) _kind(LinkKind k) => switch (k) {
        LinkKind.collaborationMine => (Icons.handshake_rounded, 'Colaboración en tu música'),
        LinkKind.collaboration => (Icons.group_rounded, 'Colaboración'),
        LinkKind.style => (Icons.graphic_eq_rounded, 'Estilo parecido'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.around == null ? 'Descubrir por conexiones' : 'Conexiones de ${widget.around}'),
        actions: [IconButton(tooltip: 'Buscar otra vez', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<ArtistDiscovery>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.around == null
                      ? 'Aún no tengo suficientes artistas tuyos, o no hay internet. Escucha un poco más y vuelve.'
                      : 'No encontré artistas nuevos conectados con ${widget.around}.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Artistas que todavía no escuchas, conectados con los tuyos. Los que unen a varios de tus '
                'artistas salen primero.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              for (final d in list)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(d.name, style: theme.textTheme.titleMedium)),
                            if (d.seeds.length >= 2)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Chip(label: Text('Puente'), visualDensity: VisualDensity.compact),
                              ),
                            IconButton(
                              tooltip: 'Poner',
                              icon: const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan),
                              onPressed: () => widget.assistant.handleSearch(SearchRequest(d.query)),
                            ),
                          ],
                        ),
                        Text(d.reason, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final l in d.links)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(_kind(l.kind).$1, size: 16),
                                label: Text('${_kind(l.kind).$2} · ${l.seed}'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Fuentes: tus canciones (artistas invitados) y Deezer (colaboraciones en sus canciones más '
                  'escuchadas y artistas relacionados). Productores: no disponibles en fuentes gratuitas confiables.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
