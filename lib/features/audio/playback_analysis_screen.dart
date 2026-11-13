import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../music_profile/music_profile.dart';

/// Análisis de reproducción: cada sesión con tiempo real escuchado, canciones,
/// saltos, terminadas, continuidad y variedad. Todo con tu historial local.
class PlaybackAnalysisScreen extends StatelessWidget {
  const PlaybackAnalysisScreen({super.key, required this.profile});
  final MusicProfile profile;

  static String _dur(Duration d) => d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = profile.sessionReports();
    final total = sessions.fold<Duration>(Duration.zero, (a, s) => a + s.listened);
    final songs = sessions.fold<int>(0, (a, s) => a + s.songs);
    final skips = sessions.fold<int>(0, (a, s) => a + s.skips);
    return Scaffold(
      appBar: AppBar(title: const Text('Análisis de reproducción')),
      body: sessions.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Aún no hay sesiones para analizar.')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                NeonCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat(theme, _dur(total), 'escuchado'),
                      _stat(theme, '$songs', 'canciones'),
                      _stat(theme, '${songs == 0 ? 0 : (skips / songs * 100).round()} %', 'saltadas'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text('Últimas ${sessions.length} sesiones', style: theme.textTheme.titleMedium),
                ),
                for (final s in sessions)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: s.skipRate > 40
                            ? Neon.pink.withValues(alpha: .2)
                            : theme.colorScheme.secondaryContainer,
                        child: Text('${s.songs}'),
                      ),
                      title: Text('${s.start.day}/${s.start.month} · '
                          '${TimeOfDay.fromDateTime(s.start).format(context)} – ${TimeOfDay.fromDateTime(s.end).format(context)}'),
                      subtitle: Text('${_dur(s.listened)} escuchados · ${s.completes} terminadas · '
                          '${s.skips} saltadas (${s.skipRate} %) · racha de ${s.longestStreak} sin saltar · '
                          '${s.artists} artistas'),
                      isThreeLine: true,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'El tiempo escuchado es una estimación: cuenta hasta 8 minutos por canción, '
                  'del momento en que empezó a la siguiente.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label) => Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      );
}
