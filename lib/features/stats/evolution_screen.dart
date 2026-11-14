import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../music_profile/music_profile.dart';
import 'evolution.dart';

/// Línea de tiempo de tu evolución musical: etapas, meses y descubrimientos.
class EvolutionScreen extends StatelessWidget {
  const EvolutionScreen({super.key, required this.profile});
  final MusicProfile profile;

  static String _min(Duration d) => d.inHours > 0 ? '${d.inHours} h' : '${d.inMinutes} min';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = TasteEvolution.from(profile);
    final months = e.months.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tu evolución musical')),
      body: months.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Escucha un poco más y aquí verás tu historia.')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                NeonCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppIcon(Icons.timeline_rounded, colors: AppColors.devices, size: 42),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e.summary(), style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
                if (e.stages.length >= 2) ...[
                  const SizedBox(height: 8),
                  Text('Tus etapas', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 74,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final s in e.stages)
                          Container(
                            width: 150,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(colors: [
                                Neon.cyan.withValues(alpha: .25),
                                Neon.cyan.withValues(alpha: .08),
                              ]),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(
                                  s.months == 1
                                      ? TasteEvolution.monthLabel(s.from)
                                      : '${TasteEvolution.monthLabel(s.from)} – ${TasteEvolution.monthLabel(s.to)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Mes a mes', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final (i, m) in months.indexed)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // La línea de tiempo.
                        SizedBox(
                          width: 26,
                          child: Column(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                margin: const EdgeInsets.only(top: 18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == 0 ? Neon.cyan : theme.colorScheme.outlineVariant,
                                  border: Border.all(color: Neon.cyan, width: 2),
                                ),
                              ),
                              if (i < months.length - 1)
                                Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(TasteEvolution.monthLabel(m.month).toUpperCase(),
                                            style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.2)),
                                      ),
                                      Text('${m.plays} canciones · ${_min(m.listened)}', style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (m.topArtist != null)
                                    Text('Artista del mes: ${m.topArtist}',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  if (m.topSong != null) Text('La que más sonó: «${m.topSong}»'),
                                  if (m.newArtists.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final a in m.newArtists.take(6))
                                          Chip(
                                            avatar: const Icon(Icons.fiber_new_rounded, size: 16),
                                            label: Text(a),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        if (m.newArtists.length > 6) Chip(label: Text('+${m.newArtists.length - 6}')),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Hecho con tu historial en el teléfono (hasta ~un año). En modo privado no se guarda nada.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}
