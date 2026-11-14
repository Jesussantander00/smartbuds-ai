import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/ui/futuristic.dart';
import 'catalog.dart';
import 'smartbuds_player.dart';
import 'youtube_engine.dart';

/// Reproductor integrado, siempre visible abajo en todas las secciones.
/// Con YouTube, el video se ve (mínimo 200×200, regla del reproductor
/// incrustado); al minimizarlo, el video se pausa.
class InAppPlayerDock extends StatelessWidget {
  const InAppPlayerDock({super.key, required this.player});
  final SmartBudsPlayer player;

  static String _time(int ms) {
    final s = (ms / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final t = player.current;
        if (t == null && !player.panelOpen) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final yt = player.engineIfCreated(InAppSource.youtube);
        final showVideo = t?.source == InAppSource.youtube && !player.minimized;
        final height = MediaQuery.of(context).size.height;
        return Glass(
          radius: 22,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // El video de YouTube sigue en el árbol (si no, se detendría);
                    // minimizado no se muestra y queda en pausa.
                    if (yt is YouTubeEngine)
                      Offstage(
                        offstage: !showVideo,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(width: 200, height: 200, child: WebViewWidget(controller: yt.controller)),
                        ),
                      ),
                    if (!showVideo)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: t.artwork == null
                              ? const ColoredBox(color: Colors.black26, child: Icon(Icons.music_note_rounded))
                              : Image.network(t.artwork!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded)),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                          if (t.artist != null)
                            Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                          const SizedBox(height: 2),
                          Text('${t.sourceLabel} · en SmartBuds',
                              style: theme.textTheme.labelSmall?.copyWith(color: t.isPreview ? Colors.amber : Neon.cyan)),
                          if (player.durationMs != null && player.durationMs! > 0)
                            Row(
                              children: [
                                Text(_time(player.positionMs), style: theme.textTheme.labelSmall),
                                Expanded(
                                  child: Slider(
                                    value: player.positionMs.clamp(0, player.durationMs!).toDouble(),
                                    max: player.durationMs!.toDouble(),
                                    onChanged: (v) => player.seek(v.round()),
                                  ),
                                ),
                                Text(_time(player.durationMs!), style: theme.textTheme.labelSmall),
                              ],
                            ),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Anterior',
                                onPressed: player.previous,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              IconButton.filled(
                                tooltip: player.isPlaying ? 'Pausa' : 'Reproducir',
                                onPressed: player.toggle,
                                icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              ),
                              IconButton(
                                tooltip: 'Siguiente',
                                onPressed: () {
                                  final f = player.onNextRequested;
                                  f != null ? f() : player.nextResult();
                                },
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                              IconButton(
                                tooltip: player.panelOpen ? 'Ocultar resultados' : 'Resultados',
                                onPressed: player.togglePanel,
                                icon: Icon(player.panelOpen ? Icons.expand_more_rounded : Icons.queue_music_rounded),
                              ),
                              if (t.source == InAppSource.youtube)
                                IconButton(
                                  tooltip: player.minimized ? 'Ver video' : 'Minimizar (pausa el video)',
                                  onPressed: player.toggleMinimized,
                                  icon: Icon(player.minimized ? Icons.ondemand_video_rounded : Icons.minimize_rounded),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (player.error != null && player.error != 'not_embeddable')
                Text(player.error!, style: theme.textTheme.bodySmall?.copyWith(color: Neon.pink)),
              if (player.panelOpen)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height * .42),
                  child: _Results(player: player),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.player});
  final SmartBudsPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = player.results;
    if (player.searching) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    if (r.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          player.lastQuery == null
              ? 'Di «busca …» o escribe en Buscar: los resultados aparecen aquí.'
              : 'Ninguna fuente integrada tiene «${player.lastQuery}».',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 6),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Resultados para «${player.lastQuery}»', style: theme.textTheme.labelLarge),
        ),
        for (final t in r)
          ListTile(
            dense: true,
            selected: t.id == player.current?.id,
            leading: Icon(switch (t.source) {
              InAppSource.youtube => Icons.ondemand_video_rounded,
              InAppSource.audius => Icons.graphic_eq_rounded,
              InAppSource.deezerPreview => Icons.timer_rounded,
            }),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${t.artist ?? ''} · ${t.sourceLabel}', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => player.play(t),
          ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            'Completa: YouTube (reproductor oficial, el video se ve) y Audius. Deezer: solo 30 s de vista previa. '
            'Spotify y Apple Music no permiten reproducir su catálogo dentro de otra app.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
