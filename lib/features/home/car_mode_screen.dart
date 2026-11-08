import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';
import '../devices/detected_player_controller.dart';

/// Modo carro: botones gigantes, fáciles de tocar sin mirar, y el título
/// de la canción en letra grande. La voz sigue funcionando igual.
class CarModeScreen extends StatelessWidget {
  const CarModeScreen({
    super.key,
    required this.controller,
    required this.assistant,
    this.voice,
  });

  final DetectedPlayerController controller;
  final Assistant assistant;
  final VoiceEngine? voice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Modo carro'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, if (voice != null) voice!]),
          builder: (context, _) {
            final d = controller.detection;
            final status = d is PlayerDetected ? d.candidate.status : null;
            final playing = status?.isPlaying ?? false;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    status?.title ?? 'Nada sonando',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
                  ),
                  if ((status?.artist ?? '').isNotEmpty)
                    Text(status!.artist!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 22)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        _Big(
                          icon: Icons.skip_previous,
                          label: 'Devuelve',
                          onTap: () => assistant.handleCommand(MusicCommand.previous),
                        ),
                        _Big(
                          icon: playing ? Icons.pause : Icons.play_arrow,
                          label: playing ? 'Pausa' : 'Sigue',
                          color: scheme.primary,
                          onTap: () => assistant.handleCommand(MusicCommand.togglePlayPause),
                        ),
                        _Big(
                          icon: Icons.skip_next,
                          label: 'Cambia',
                          onTap: () => assistant.handleCommand(MusicCommand.next),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _Big(
                          icon: Icons.favorite,
                          label: 'Me gusta',
                          onTap: () => assistant.handleIntent(const LikeIntent()),
                        ),
                        _Big(
                          icon: voice?.enabled == true ? Icons.mic : Icons.mic_off,
                          label: voice?.enabled == true ? 'Escuchando' : 'Micrófono',
                          color: voice?.enabled == true ? scheme.primary : null,
                          onTap: () => voice?.toggle(),
                        ),
                        _Big(
                          icon: Icons.auto_awesome,
                          label: 'Algo nuevo',
                          onTap: assistant.discover,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: color ?? const Color(0xFF1E2529),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: Colors.white),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
