import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import 'music_profile.dart';

/// «Tu año en música»: el resumen de los últimos 365 días.
class YearInMusicScreen extends StatelessWidget {
  const YearInMusicScreen({super.key, required this.profile, required this.assistant});

  final MusicProfile profile;
  final Assistant assistant;

  static const _months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = profile.summary(days: 365);
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 365));

    // Reproducciones por mes (los últimos 12) y top canciones/artistas del año.
    final perMonth = List<int>.filled(12, 0);
    final songs = <String, int>{};
    final artists = <String, int>{};
    DateTime? first;
    for (final e in profile.history) {
      if (e.type != ListenEventType.play || e.at.isBefore(from)) continue;
      first ??= e.at;
      final monthsAgo = (now.year - e.at.year) * 12 + now.month - e.at.month;
      if (monthsAgo >= 0 && monthsAgo < 12) perMonth[11 - monthsAgo]++;
      songs[e.key] = (songs[e.key] ?? 0) + 1;
      final a = profile.tracks[e.key]?.artist;
      if (a != null && a.isNotEmpty) artists[a] = (artists[a] ?? 0) + 1;
    }
    List<MapEntry<String, int>> top(Map<String, int> m) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
    final topSongs = top(songs);
    final topArtists = top(artists);
    final maxMonth = perMonth.fold<int>(1, (a, b) => b > a ? b : a);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu año en música'),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share),
            onPressed: () => assistant.shareSummary(days: 365),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          NeonCard(
            child: Column(
              children: [
                Text('${s.plays}', style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
                const Text('canciones'),
                const SizedBox(height: 8),
                Text('~${(s.minutes / 60).toStringAsFixed(s.minutes < 600 ? 1 : 0)} horas de música',
                    style: theme.textTheme.titleMedium),
                if (first != null && now.difference(first).inDays < 330)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Desde ${first.day}/${first.month}/${first.year}, cuando SmartBuds empezó a aprender.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Mes a mes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 12; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: 90 * perMonth[i] / maxMonth + 2,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            gradient: Neon.gradient,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_months[(now.month - 12 + i + 12) % 12],
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Tus artistas del año', style: theme.textTheme.titleMedium),
          if (topArtists.isEmpty) const Text('Aún no hay datos.'),
          for (var i = 0; i < topArtists.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(topArtists[i].key),
              trailing: Text('${topArtists[i].value}'),
            ),
          const SizedBox(height: 12),
          Text('Tus canciones del año', style: theme.textTheme.titleMedium),
          if (topSongs.isEmpty) const Text('Aún no hay datos.'),
          for (var i = 0; i < topSongs.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(profile.tracks[topSongs[i].key]?.title ?? topSongs[i].key),
              subtitle: Text(profile.tracks[topSongs[i].key]?.artist ?? ''),
              trailing: Text('${topSongs[i].value}'),
            ),
          if (profile.favoriteDaypart != null) ...[
            const SizedBox(height: 12),
            Text('Escuchas más ${profile.favoriteDaypart!.label}.', style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}
