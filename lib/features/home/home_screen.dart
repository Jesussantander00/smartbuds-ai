import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';
import '../devices/detected_player_controller.dart';

/// Inicio: qué suena, el micrófono y la búsqueda rápida.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.assistant,
    this.voice,
  });

  final DetectedPlayerController controller;
  final Assistant assistant;
  final VoiceEngine? voice;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.controller, if (widget.voice != null) widget.voice!];
    return Scaffold(
      appBar: AppBar(title: const Text('SmartBuds AI')),
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _NowPlaying(detection: widget.controller.detection),
            const SizedBox(height: 16),
            if (widget.voice != null) _MicCard(voice: widget.voice!),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => widget.controller.search(_query.text),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Buscar una canción',
                      hintText: 'Ojalá Ryan Castro',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Buscar',
                  onPressed: widget.controller.busy
                      ? null
                      : () => widget.controller.search(_query.text),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: widget.controller.busy ? null : widget.assistant.playFavorite,
              icon: const Icon(Icons.favorite),
              label: const Text('Pon algo que me guste'),
            ),
            if (widget.controller.lastResult != null) ...[
              const SizedBox(height: 12),
              _ResultLine(result: widget.controller.lastResult!),
            ],
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.detection});
  final DetectionResult detection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String app, String? song) = switch (detection) {
      PlayerDetected(:final candidate) => (
          candidate.status.appName,
          candidate.status.title == null
              ? null
              : '${candidate.status.title}'
                  '${candidate.status.artist != null ? ' — ${candidate.status.artist}' : ''}',
        ),
      NeedsChoice() => ('Varios reproductores', 'Revisa la pestaña Dispositivos'),
      NoPlayer() => ('Sin música', 'Pon algo en tu app de música o di «Busca…»'),
    };
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.graphic_eq, size: 40, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app, style: theme.textTheme.labelLarge),
                  if (song != null) Text(song, style: theme.textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicCard extends StatelessWidget {
  const _MicCard({required this.voice});
  final VoiceEngine voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = voice.enabled;
    final status = !on
        ? 'Toca para que SmartBuds te escuche'
        : voice.askingForSong
            ? '¿Qué canción? Dila ahora…'
            : voice.paused
                ? 'En pausa: conecta tus audífonos para seguir'
                : voice.listening
                    ? 'Escuchando, también con la pantalla apagada'
                    : 'Preparando el micrófono…';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            IconButton.filled(
              iconSize: 56,
              tooltip: on ? 'Dejar de escuchar' : 'Escuchar',
              onPressed: voice.toggle,
              icon: Icon(on ? (voice.paused ? Icons.mic_off : Icons.mic) : Icons.mic_none),
            ),
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
            if (voice.lastHeard.isNotEmpty)
              Text('Oí: «${voice.lastHeard}»', style: theme.textTheme.bodySmall),
            if (voice.error != null)
              Text(voice.error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(voice.headphonesConnected ? Icons.headphones : Icons.headset_off,
                  size: 18),
              label: Text(voice.headphonesConnected
                  ? 'Audífonos conectados'
                  : 'Sin audífonos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});
  final CommandResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.executed;
    return ListTile(
      leading: Icon(ok ? Icons.check_circle : Icons.info_outline,
          color: ok ? Colors.green : Colors.orange),
      title: Text(result.message),
    );
  }
}
