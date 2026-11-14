import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../music_profile/music_profile.dart';
import 'advanced_stats.dart';

/// Estadísticas avanzadas: artistas, horarios, rachas y descubrimientos.
class AdvancedStatsScreen extends StatelessWidget {
  const AdvancedStatsScreen({super.key, required this.profile});
  final MusicProfile profile;

  static String dur(Duration d) => d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AdvancedStats.from(profile);
    final top = s.artists.take(10).toList();
    final maxTime = top.isEmpty ? 1 : top.first.listened.inSeconds.clamp(1, 1 << 31);
    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas avanzadas')),
      body: s.artists.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Escucha un poco de música y vuelve.')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: [
                    _tile(theme, Icons.timer_outlined, AppColors.home, dur(s.listened), 'escuchado'),
                    _tile(theme, Icons.local_fire_department_rounded, AppColors.assistant,
                        '${s.currentStreak} ${s.currentStreak == 1 ? 'día' : 'días'}', 'racha (mejor: ${s.bestStreak})'),
                    _tile(theme, Icons.person_rounded, AppColors.music, '${s.artists.length}', 'artistas · ${s.songs} canciones'),
                    _tile(theme, Icons.schedule_rounded, AppColors.stats,
                        '${s.peakHour.toString().padLeft(2, '0')}:00', 'tu hora favorita'),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Tus artistas', style: theme.textTheme.titleMedium),
                Text(
                  'Tu número 1 se lleva el ${s.topShare} % de tu tiempo.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                NeonCard(
                  child: Column(
                    children: [
                      for (final (i, a) in top.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(width: 24, child: Text('${i + 1}', style: theme.textTheme.labelLarge)),
                                  Expanded(
                                    child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  Text(dur(a.listened), style: theme.textTheme.bodySmall),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: a.listened.inSeconds / maxTime,
                                    minHeight: 6,
                                    color: Neon.cyan,
                                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 24, top: 3),
                                child: Text(
                                  '${a.plays} reproducciones · ${a.songs} canciones · '
                                  'terminas el ${a.completionRate} %${a.likes > 0 ? ' · ${a.likes} ♥' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('Cuándo escuchas', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                NeonCard(child: _Heatmap(heat: s.heat)),
                const SizedBox(height: 14),
                Text('Descubrimientos (30 días)', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                NeonCard(
                  child: s.discoveries.isEmpty
                      ? const Text('Este mes no apareció ningún artista nuevo. Di «pon algo nuevo».')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.discoveries.length} artistas nuevos · se quedaron ${s.keepers.length} (${s.discoveryRate} %)',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final a in s.discoveries.take(20))
                                  Chip(
                                    avatar: Icon(s.keepers.contains(a) ? Icons.favorite : Icons.fiber_new_rounded, size: 16),
                                    label: Text(a.name),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Todo se calcula en tu teléfono con tu historial (${s.activeDays} días con música). '
                  'El tiempo es estimado (hasta 8 min por canción). Las apps de música no comparten '
                  'el género ni el álbum con otras apps, así que no se muestran.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }

  Widget _tile(ThemeData theme, IconData icon, List<Color> colors, String value, String label) => NeonCard(
        child: Row(
          children: [
            AppIcon(icon, colors: colors, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Mapa de calor: días (filas) × franjas de 3 horas (columnas).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.heat});
  final List<List<int>> heat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    final cells = [
      for (final row in heat) [for (var b = 0; b < 8; b++) row.sublist(b * 3, b * 3 + 3).fold<int>(0, (a, v) => a + v)],
    ];
    final maxV = cells.expand((r) => r).fold<int>(0, (a, v) => v > a ? v : a);
    return Column(
      children: [
        for (var d = 0; d < 7; d++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 20, child: Text(days[d], style: theme.textTheme.labelSmall)),
                for (var b = 0; b < 8; b++)
                  Expanded(
                    child: Container(
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: maxV == 0
                            ? theme.colorScheme.surfaceContainerHighest
                            : Color.lerp(theme.colorScheme.surfaceContainerHighest, Neon.cyan, cells[d][b] / maxV),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 20),
            for (final h in ['0', '3', '6', '9', '12', '15', '18', '21'])
              Expanded(child: Text(h, textAlign: TextAlign.center, style: theme.textTheme.labelSmall)),
          ],
        ),
      ],
    );
  }
}
