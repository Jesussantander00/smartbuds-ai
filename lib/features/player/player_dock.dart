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

  static String _dur(int? ms) {
    if (ms == null) return '';
    final s = (ms / 1000).round();
    return ' · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = player.results;
    if (player.searching) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    final q = player.lastQuery;
    if (r.isEmpty && player.albums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q == null
                  ? 'Di «busca …» o escribe en Buscar: los resultados aparecen aquí.'
                  : 'No puedo reproducir «$q» dentro de SmartBuds: ninguna fuente integrada la tiene.',
              style: theme.textTheme.bodySmall,
            ),
            if (q != null) _external(context, q),
          ],
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 6),
      children: [
        if (q != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Resultados para «$q»', style: theme.textTheme.labelLarge),
          ),
        if (player.albums.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in player.albums)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4),
                    child: ActionChip(
                      avatar: const Icon(Icons.album_rounded, size: 16),
                      label: Text('${a.title}${a.artist == null ? '' : ' · ${a.artist}'}'),
                      onPressed: player.onAlbum == null ? null : () => player.onAlbum!(a),
                    ),
                  ),
              ],
            ),
          ),
        for (final (i, res) in r.indexed)
          ListTile(
            dense: true,
            selected: res.key == player.currentResult?.key,
            leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
            title: Text(res.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${res.artist ?? ''}${res.album == null ? '' : ' · ${res.album}'}${_dur(res.durationMs)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final (j, o) in res.options.indexed)
                      InkWell(
                        onTap: () => player.playResult(res, option: j),
                        child: Text(
                          o.sourceLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: o.isPreview ? Colors.amber : Neon.cyan,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: Icon(res.hasFull ? Icons.play_circle_rounded : Icons.timer_rounded,
                color: res.hasFull ? Neon.cyan : Colors.amber),
            onTap: () => player.playResult(res),
          ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            'Completas: YouTube (reproductor oficial, el video se ve) y Audius. Deezer y Apple: 30 s de vista previa. '
            'Spotify, Apple Music y SoundCloud no se pueden reproducir dentro de SmartBuds hoy (ver Fuentes musicales).',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// Abrir en otra app: solo si tú lo tocas (nunca automático).
  Widget _external(BuildContext context, String q) => player.onOpenExternal == null
      ? const SizedBox.shrink()
      : Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Buscarla en mi app de música (sale de SmartBuds)'),
            onPressed: () => player.onOpenExternal!(q),
          ),
        );
}
