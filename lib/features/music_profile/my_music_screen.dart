import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/account_card.dart';
import 'weekly_stats.dart';
import '../account/supabase_auth.dart';
import '../assistant/assistant.dart';
import 'music_profile.dart';
import 'supabase_sync.dart';
import 'year_in_music_screen.dart';
import 'insights.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';

/// Mi música: lo que SmartBuds aprendió de tus gustos.
class MyMusicScreen extends StatelessWidget {
  const MyMusicScreen({
    super.key,
    required this.profile,
    required this.assistant,
    this.sync,
    this.auth,
  });

  final MusicProfile profile;
  final Assistant assistant;
  final SupabaseSync? sync;
  final SupabaseAuth? auth;

  static String _eventLabel(ListenEventType t) => switch (t) {
        ListenEventType.play => 'Sonó',
        ListenEventType.complete => 'Escuchada completa',
        ListenEventType.skip => 'Saltada',
        ListenEventType.repeat => 'Repetida',
        ListenEventType.like => 'Me gusta',
        ListenEventType.dislike => 'No me gusta',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi música')),
      body: ListenableBuilder(
        listenable: profile,
        builder: (context, _) {
          final artists = profile.topArtists(5);
          final plays = profile.tracks.values.fold<int>(0, (s, t) => s + t.plays);
          final likes = profile.tracks.values.where((t) => t.likes > 0).length;
          final recent = profile.history.reversed.take(20).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
            children: [
              if (auth != null) ...[
                AccountCard(auth: auth!),
                const SizedBox(height: 12),
              ],
              _IdentityCard(profile: profile),
              InsightsSection(profile: profile, assistant: assistant),
              BrainSection(assistant: assistant),
              const SizedBox(height: 12),
              WeeklyStatsCard(profile: profile),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: 'Canciones', value: '${profile.tracks.length}'),
                  _Stat(label: 'Reproducciones', value: '$plays'),
                  _Stat(label: 'Favoritas', value: '$likes'),
                ],
              ),
              if (profile.favoriteDaypart != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Lo que más disfrutas lo escuchas ${profile.favoriteDaypart!.label}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: assistant.discover,
                      icon: const Icon(Icons.explore),
                      label: const Text('Algo nuevo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: assistant.playFavorite,
                icon: const Icon(Icons.favorite),
                label: const Text('Pon algo que me guste'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.history_toggle_off, size: 18),
                    label: const Text('Favoritas olvidadas'),
                    onPressed: assistant.playForgotten,
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Compartir mi semana'),
                    onPressed: () => assistant.shareSummary(days: 7),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Tu año en música'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => YearInMusicScreen(profile: profile, assistant: assistant),
                    )),
                  ),
                ],
              ),
              if (artists.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ArtistCarousel(artists: [for (final (a, _) in artists) a], assistant: assistant),
              ],
              const SizedBox(height: 20),
              _TopTracksSection(profile: profile, assistant: assistant),
              const SizedBox(height: 12),
              Text('Listas por duración', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [15, 30, 45, 60])
                    ActionChip(
                      avatar: const Icon(Icons.timer_outlined, size: 18),
                      label: Text('$m min'),
                      onPressed: () => assistant.playFor(m),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Tus gustos', style: theme.textTheme.titleMedium),
              Card(
                child: Column(
                  children: [
                    Builder(builder: (context) {
                      final dups = profile.duplicateGroups();
                      if (dups.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined),
                        title: Text('Limpiar duplicados (${dups.length})'),
                        subtitle: Text('Ej.: ${dups.first.map((t) => '«${t.title}»').take(2).join(' y ')}'),
                        onTap: () {
                          final n = profile.mergeDuplicates();
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Listo: uní $n canciones repetidas.')));
                        },
                      );
                    }),
                    ListTile(
                      leading: const Icon(Icons.compare_arrows),
                      title: const Text('Comparar gustos con un amigo'),
                      subtitle: const Text('Envía tu código y pega el de tu amigo.'),
                      onTap: () => _compare(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Exportar copia de mis gustos'),
                      subtitle: const Text('Guárdala o pásala a otro teléfono.'),
                      onTap: () async {
                        final ok = await assistant.media?.shareText(profile.exportJson()) ?? false;
                        if (!ok) {
                          await Clipboard.setData(ClipboardData(text: profile.exportJson()));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copia guardada en el portapapeles.')));
                          }
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Importar una copia'),
                      subtitle: const Text('Pega el texto que exportaste.'),
                      onTap: () => _import(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Historial reciente', style: theme.textTheme.titleMedium),
              for (final e in recent)
                ListTile(
                  dense: true,
                  title: Text(profile.tracks[e.key]?.title ?? e.key),
                  subtitle: Text(_eventLabel(e.type)),
                  trailing: Text(
                      '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}'),
                ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(sync == null ? Icons.phone_android : Icons.cloud_done),
                title: Text(sync == null
                    ? 'Guardado solo en este teléfono'
                    : 'Sincronizado con Supabase'),
                subtitle: Text(sync == null
                    ? 'Agrega SUPABASE_URL y SUPABASE_ANON_KEY a secrets.json para respaldarlo en la nube.'
                    : sync!.lastError ?? 'Funcionando'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('¿Borrar tu perfil musical?'),
                      content: const Text(
                          'SmartBuds olvidará tu historial y tus favoritas en este teléfono.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Borrar')),
                      ],
                    ),
                  );
                  if (ok == true) await profile.clear();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Borrar mi perfil'),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension on MyMusicScreen {
  Future<String?> _askText(BuildContext context, String title, String hint) async {
    final ctrl = TextEditingController();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) ctrl.text = data!.text!;
    if (!context.mounted) return null;
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(border: const OutlineInputBorder(), hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Listo')),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  Future<void> _import(BuildContext context) async {
    final text = await _askText(context, 'Importar copia', 'Pega aquí la copia');
    if (text == null || !context.mounted) return;
    final n = profile.importJson(text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n < 0 ? 'Ese texto no es una copia de SmartBuds.' : 'Listo: $n canciones unidas a tu perfil.')));
  }

  Future<void> _compare(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Enviar mi código'),
              onTap: () => Navigator.pop(c, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Pegar el código de mi amigo'),
              onTap: () => Navigator.pop(c, 'paste'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'send') {
      final code = profile.tasteCode();
      final ok = await assistant.media?.shareText(
              '¿Qué tanto se parecen nuestros gustos? Pega esto en SmartBuds AI → '
              'Mi música → Comparar gustos:\n$code') ??
          false;
      if (!ok) await Clipboard.setData(ClipboardData(text: code));
      return;
    }
    if (choice != 'paste') return;
    final code = await _askText(context, 'Código de tu amigo', 'SB1:…');
    if (code == null || !context.mounted) return;
    final r = profile.compareTaste(code);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r == null ? 'Código no válido' : 'Afinidad: ${r.percent} %'),
        content: Text(r == null
            ? 'Pídele a tu amigo que vuelva a enviar su código.'
            : r.shared.isEmpty
                ? 'No tienen artistas en común… ¡aún! Buen momento para recomendarse música.'
                : 'En común: ${r.shared.join(', ')}.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }
}

/// Tus canciones: actuales (este mes), clásicos o todas, con menú para editarlas.
class _TopTracksSection extends StatefulWidget {
  const _TopTracksSection({required this.profile, required this.assistant});
  final MusicProfile profile;
  final Assistant assistant;

  @override
  State<_TopTracksSection> createState() => _TopTracksSectionState();
}

class _TopTracksSectionState extends State<_TopTracksSection> {
  String _view = 'now';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;
    final assistant = widget.assistant;
    final top = switch (_view) {
      'now' => profile.currentFavorites(),
      'classic' => profile.classics(),
      _ => profile.topTracks(10),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tus canciones', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'now', label: Text('Actuales')),
            ButtonSegment(value: 'classic', label: Text('Clásicos')),
            ButtonSegment(value: 'all', label: Text('Todas')),
          ],
          selected: {_view},
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        const SizedBox(height: 4),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(switch (_view) {
              'now' => 'Este mes aún no hay favoritas. Escucha música y di «me gusta».',
              'classic' => 'Todavía no tienes clásicos: todo lo que te gusta lo escuchas seguido.',
              _ => 'Todavía no hay suficiente información. Escucha música con SmartBuds activo '
                  'y di «me gusta» cuando algo te encante.',
            }),
          ),
        if (top.isNotEmpty)
          Text('Toca ⋮ para editar tus gustos.', style: theme.textTheme.bodySmall),
        for (final t in top)
          ListTile(
            dense: true,
            leading: const Icon(Icons.music_note),
            title: Text(t.title),
            subtitle: Text(t.artist ?? ''),
            onTap: () => assistant
                .handleSearch(SearchRequest([t.title, if (t.artist != null) t.artist].join(' '))),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.score(profile.weights).toStringAsFixed(0)),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'like':
                        profile.likeTrack(t.key);
                      case 'remove':
                        profile.removeTrack(t.key);
                      case 'block':
                        assistant.settings?.block(title: t.title, artist: t.artist);
                        profile.removeTrack(t.key);
                      case 'blockArtist':
                        assistant.settings?.block(artist: t.artist, wholeArtist: true);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'like', child: Text('Me gusta más')),
                    const PopupMenuItem(value: 'remove', child: Text('Quitar de mis gustos')),
                    const PopupMenuItem(value: 'block', child: Text('Nunca más esta')),
                    if ((t.artist ?? '').isNotEmpty)
                      PopupMenuItem(value: 'blockArtist', child: Text('Bloquear a ${t.artist}')),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tus artistas favoritos como tarjetas que se deslizan, con su foto.
class _ArtistCarousel extends StatelessWidget {
  const _ArtistCarousel({required this.artists, required this.assistant});
  final List<String> artists;
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.78),
        itemCount: artists.length,
        itemBuilder: (context, i) {
          final name = artists[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<String?>(
                    future: assistant.similar?.pictureOf(name),
                    builder: (context, snap) => snap.data == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                theme.colorScheme.primary.withValues(alpha: .5),
                                theme.colorScheme.tertiary.withValues(alpha: .5),
                              ]),
                            ),
                            child: const Center(child: Icon(Icons.person, size: 64)),
                          )
                        : Image.network(snap.data!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${i + 1} DE TUS ARTISTAS',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: Colors.white70, letterSpacing: 1.2)),
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Pon algo de $name',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => assistant.handleSearch(SearchRequest(name)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tu identidad musical en una tarjeta: un perfil con nombre propio.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile});
  final MusicProfile profile;

  /// Un «tipo de oyente» a partir de cómo escuchas.
  (String, String, IconData) _persona() {
    final artists = profile.topArtists(50);
    if (profile.tracks.length < 5 || artists.isEmpty) {
      return ('Recién llegado', 'Sigue escuchando: SmartBuds está aprendiendo.', Icons.auto_awesome);
    }
    final total = artists.fold<double>(0, (a, e) => a + e.$2);
    final topShare = total == 0 ? 0 : artists.first.$2 / total;
    if (topShare > .4) {
      return ('Fan de ${artists.first.$1}', 'Tu artista favorito domina tu música.', Icons.star_rounded);
    }
    if (artists.length >= 15) {
      return ('Explorador', 'Escuchas a muchos artistas distintos.', Icons.explore_rounded);
    }
    final night = profile.favoriteDaypart == Daypart.noche || profile.favoriteDaypart == Daypart.madrugada;
    if (night) return ('Oyente nocturno', 'Tu mejor música suena de noche.', Icons.nightlight_round);
    return ('Equilibrado', 'Mezclas favoritos y cosas nuevas.', Icons.balance_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (name, desc, icon) = _persona();
    final top = profile.topArtists(3).map((e) => e.$1).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.secondaryContainer, theme.colorScheme.surface],
        ),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Neon.gradient),
            child: Icon(icon, size: 34, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TU PERFIL MUSICAL',
                    style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.4, color: Neon.cyan)),
                Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(desc, style: theme.textTheme.bodySmall),
                if (top.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(top.join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}
