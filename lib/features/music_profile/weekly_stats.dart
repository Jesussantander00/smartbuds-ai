import 'package:flutter/material.dart';

import 'music_profile.dart';

/// Resumen semanal con gráficos sencillos (sin librerías): canciones por día
/// y por momento del día, canción y artista de la semana.
class WeeklyStatsCard extends StatelessWidget {
  const WeeklyStatsCard({super.key, required this.profile});

  final MusicProfile profile;

  static const _days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final s = profile.summary();
    final theme = Theme.of(context);
    if (s.plays == 0) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.insights),
          title: Text('Tu semana'),
          subtitle: Text('Escucha música unos días y aquí verás tu resumen.'),
        ),
      );
    }
    final hours = s.minutes ~/ 60;
    final mins = s.minutes % 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu semana', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${s.plays} canciones · ≈ ${hours > 0 ? '$hours h ' : ''}$mins min de música'),
            if (s.topSong != null)
              Text('Canción de la semana: ${s.topSong!.title}'
                  '${(s.topSong!.artist ?? '').isEmpty ? '' : ' — ${s.topSong!.artist}'}'),
            if (s.topArtist != null) Text('Artista de la semana: ${s.topArtist}'),
            const SizedBox(height: 16),
            _Bars(
              values: s.playsPerDay,
              labels: [
                for (var i = 0; i < s.playsPerDay.length; i++)
                  _days[s.from.add(Duration(days: i)).weekday - 1],
              ],
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Cuándo escuchas', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final d in Daypart.values)
              _Line(
                label: switch (d) {
                  Daypart.madrugada => 'Madrugada',
                  Daypart.manana => 'Mañana',
                  Daypart.tarde => 'Tarde',
                  Daypart.noche => 'Noche',
                },
                value: s.playsPerDaypart[d] ?? 0,
                max: s.playsPerDaypart.values.fold<int>(1, (a, b) => a > b ? a : b),
                color: theme.colorScheme.tertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels, required this.color});

  final List<int> values;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${values[i]}', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Container(
                    height: 70 * values[i] / max + 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.max, required this.color});

  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / max,
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
