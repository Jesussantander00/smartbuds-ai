import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../jarvis/jarvis_core.dart';

/// Panel de acciones: lo que Jarvis te escuchó, lo que entendió (paso por
/// paso si encadenaste órdenes) y acciones rápidas para hacerlas con un toque.
class VoiceActionsCard extends StatelessWidget {
  const VoiceActionsCard({super.key, required this.voice});
  final VoiceEngine voice;

  static const _quick = <(IconData, String, VoiceIntent)>[
    (Icons.skip_next_rounded, 'Cambiar canción', CommandIntent(MusicCommand.next)),
    (Icons.pause_rounded, 'Pausa / sigue', CommandIntent(MusicCommand.togglePlayPause)),
    (Icons.search_rounded, 'Buscar…', SearchPromptIntent()),
    (Icons.explore_rounded, 'Algo nuevo', DiscoverIntent()),
    (Icons.person_search_rounded, 'Sobre este artista', ArtistInfoIntent()),
    (Icons.directions_car_rounded, 'Modo carro', CarModeIntent(true)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final last = voice.history.isEmpty ? null : voice.history.first;
        final chained = last != null && last.action.contains(' + ') && voice.lastPlan.length > 1;
        return NeonCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  JarvisCore(voice: voice, size: 64, showLabel: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Jarvis', style: theme.textTheme.titleMedium),
                        Text(JarvisCore.label(voice.jarvisState),
                            style: theme.textTheme.labelMedium?.copyWith(color: JarvisCore.color(voice.jarvisState))),
                      ],
                    ),
                  ),
                  if (voice.enabled)
                    TextButton.icon(
                      onPressed: voice.stop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Dejar de escuchar'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (last == null)
                Text('Di una orden, encadena varias con «y», o toca una acción.', style: theme.textTheme.bodyMedium)
              else ...[
                Text('Te escuché: «${last.heard}»', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                if (!chained)
                  Text('Entendí: ${last.action}', style: const TextStyle(fontWeight: FontWeight.w700))
                else ...[
                  const Text('Entendí estos pasos:', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final (i, step) in voice.lastPlan.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 10, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(step)),
                          const Icon(Icons.check_rounded, size: 18, color: Color(0xFF1FA889)),
                        ],
                      ),
                    ),
                ],
                if (last.reply != null) ...[
                  const SizedBox(height: 4),
                  Text('Respondí: ${last.reply}', style: theme.textTheme.bodySmall),
                ],
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (icon, label, intent) in _quick)
                    ActionChip(
                      avatar: Icon(icon, size: 18),
                      label: Text(label),
                      onPressed: () => voice.runIntent(intent),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
