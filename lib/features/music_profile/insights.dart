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
    final pat = profile.pattern();
    if (shift.isEmpty && tired.isEmpty && !hasEvo && pat.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('Tu inteligencia musical', style: theme.textTheme.titleMedium),
        if (!pat.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded, color: Neon.cyan),
              title: const Text('Tu rutina musical'),
              subtitle: Text([
                if (pat.weekdayStart != null)
                  'Entre semana sueles empezar a las ${ListeningPattern.hour(pat.weekdayStart!)}',
                if (pat.weekendStart != null)
                  'El fin de semana, a las ${ListeningPattern.hour(pat.weekendStart!)}',
                if (pat.typicalEnd != null) 'Sueles terminar hacia las ${ListeningPattern.hour(pat.typicalEnd!)}',
              ].join('.\n')),
            ),
          ),
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

/// Cerebro musical en «Mi música»: tus sesiones y el radar de artistas nuevos.
class BrainSection extends StatefulWidget {
  const BrainSection({super.key, required this.assistant});
  final Assistant assistant;

  @override
  State<BrainSection> createState() => _BrainSectionState();
}

class _BrainSectionState extends State<BrainSection> {
  // El radar consulta internet: se pide una vez al abrir la pantalla.
  late final Future<List<({String artist, String because, int? fans, String? picture, String? topTrack})>> _radar =
      widget.assistant.brain.radar();

  Assistant get assistant => widget.assistant;
  bool _onlyEmerging = false;

  /// Menos de esta cantidad de seguidores en Deezer = artista emergente.
  static const emergingFans = 300000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insight = assistant.brain.sessionInsight();
    final ambience = assistant.brain.ambience();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insight != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights_rounded, color: Neon.cyan),
              title: const Text('Tus mejores sesiones'),
              subtitle: Text('${insight.summary} (de ${insight.sessions} sesiones)'),
            ),
          ),
        if (ambience != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.waves_rounded, color: Neon.cyan),
              title: Text('Ambiente de ahora: ${ambience.mood}'),
              subtitle: Text('Porque ${ambience.reason}. Las próximas sugerencias van en esa línea.'),
            ),
          ),
        FutureBuilder(
          future: _radar,
          builder: (context, snap) {
            final all = snap.data ?? const [];
            if (all.isEmpty) return const SizedBox.shrink();
            final list = _onlyEmerging ? all.where((a) => a.fans != null && a.fans! < emergingFans).toList() : all;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Radar de descubrimiento', style: theme.textTheme.titleMedium)),
                    FilterChip(
                      label: const Text('Emergentes'),
                      selected: _onlyEmerging,
                      onSelected: (v) => setState(() => _onlyEmerging = v),
                    ),
                  ],
                ),
                Text(
                  'Dato real: seguidores en Deezer. Predicción de SmartBuds: que te guste, por parecerse a tus artistas. '
                  'Emergente = menos de ${_fans(emergingFans)} seguidores.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                if (list.isEmpty)
                  const Card(child: ListTile(title: Text('Ningún emergente esta vez. Vuelve más tarde.'))),
                Card(
                  child: Column(
                    children: [
                      for (final a in list.take(6))
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.secondaryContainer,
                            backgroundImage: a.picture == null ? null : NetworkImage(a.picture!),
                            child: a.picture == null ? const Icon(Icons.person) : null,
                          ),
                          title: Row(
                            children: [
                              Flexible(child: Text(a.artist)),
                              if (a.fans != null && a.fans! < emergingFans) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.trending_up_rounded, size: 16, color: Neon.cyan),
                              ],
                            ],
                          ),
                          subtitle: Text('Predicción: te puede gustar, se parece a ${a.because}'
                              '${a.fans == null ? '' : ' · Dato real: ${_fans(a.fans!)} seguidores'}'),
                          trailing: const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan),
                          onTap: () => assistant.handleSearch(
                              SearchRequest(a.topTrack == null ? a.artist : '${a.topTrack} ${a.artist}')),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _fans(int n) =>
      n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)} M' : n >= 1000 ? '${(n / 1000).round()} mil' : '$n';
}
