import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'music_profile.dart';

const _months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// «¿Por qué esta?»: lo que SmartBuds sabe de la canción que suena.
Future<void> showWhySheet(BuildContext context, Assistant assistant) {
  final a = assistant.active;
  final title = a?.title ?? '';
  final reasons = title.isEmpty
      ? const ['No hay música sonando.']
      : assistant.profile.whyYouLike(MusicProfile.keyFor(title, a?.artist));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Por qué esta canción?', style: theme.textTheme.titleLarge),
              if (title.isNotEmpty)
                Text([title, if ((a?.artist ?? '').isNotEmpty) a!.artist].join(' — '),
                    style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              for (final r in reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline, color: Neon.cyan),
                  title: Text(r),
                ),
              const SizedBox(height: 4),
              Text(
                'Se basa en cómo la escuchas (si la terminas, repites o saltas). '
                'Las apps de música no comparten datos del sonido (ritmo, energía).',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Canciones parecidas a la que suena, para poner con un toque.
Future<void> showSimilarSheet(BuildContext context, Assistant assistant) {
  final future = assistant.similarToCurrent();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: FutureBuilder<List<({String artist, String title, String? picture})>>(
        future: future,
        builder: (context, snap) {
          final theme = Theme.of(context);
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          final list = snap.data ?? const [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parecidas a esta', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No encontré canciones parecidas (¿hay música sonando con artista?).'),
                  ),
                for (final x in list.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      backgroundImage: x.picture == null ? null : NetworkImage(x.picture!),
                      child: x.picture == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(x.artist),
                    trailing: const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan, size: 32),
                    onTap: () {
                      Navigator.pop(context);
                      assistant.handleSearch(SearchRequest('${x.title} ${x.artist}'));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Inteligencia musical en «Mi música»: cambios de gusto, sobreexpuestas y evolución.
class InsightsSection extends StatelessWidget {
  const InsightsSection({super.key, required this.profile, required this.assistant});

  final MusicProfile profile;
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shift = profile.tasteShift();
    final tired = profile.overexposed();
    final evo = profile.evolution();
    final hasEvo = evo.where((e) => e.plays > 0).length >= 2;
    if (shift.isEmpty && tired.isEmpty && !hasEvo) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('Tu inteligencia musical', style: theme.textTheme.titleMedium),
        if (shift.rising.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.trending_up_rounded, color: Neon.cyan),
              title: Text('Últimamente escuchas más a ${shift.rising.join(', ')}'),
              subtitle: const Text('Tu gusto está cambiando: SmartBuds lo tiene en cuenta.'),
              trailing: IconButton(
                tooltip: 'Pon algo de ${shift.rising.first}',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => assistant.handleSearch(SearchRequest(shift.rising.first)),
              ),
            ),
          ),
        if (shift.fading.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.trending_down_rounded),
              title: Text('Casi ya no escuchas a ${shift.fading.join(', ')}'),
              subtitle: const Text('¿Lo extrañas? Tócalo para volver a escucharlo.'),
              onTap: () => assistant.handleSearch(SearchRequest(shift.fading.first)),
            ),
          ),
        if (tired.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.repeat_on_rounded, color: Neon.pink),
              title: Text(tired.length == 1
                  ? '«${tired.first.$1.title}» sonó ${tired.first.$2} veces esta semana'
                  : '${tired.length} canciones sonaron demasiado esta semana'),
              subtitle: const Text('Les doy un descanso en «Pon algo que me guste» por unos días.'),
            ),
          ),
        if (hasEvo) ...[
          const SizedBox(height: 8),
          Text('Tu evolución', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in evo)
                  Container(
                    width: 112,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: e.plays == 0 ? theme.colorScheme.surface : theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_months[e.month.month - 1],
                            style: theme.textTheme.labelMedium?.copyWith(color: Neon.cyan)),
                        const SizedBox(height: 4),
                        Text(e.artist ?? '—',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${e.plays} canciones', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
