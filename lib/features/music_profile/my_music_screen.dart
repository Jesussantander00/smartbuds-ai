import 'package:flutter/material.dart';

import '../account/account_card.dart';
import '../account/supabase_auth.dart';
import '../assistant/assistant.dart';
import 'music_profile.dart';
import 'supabase_sync.dart';

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
          final top = profile.topTracks(10);
          final artists = profile.topArtists(5);
          final plays = profile.tracks.values.fold<int>(0, (s, t) => s + t.plays);
          final likes = profile.tracks.values.where((t) => t.likes > 0).length;
          final recent = profile.history.reversed.take(20).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (auth != null) ...[
                AccountCard(auth: auth!),
                const SizedBox(height: 12),
              ],
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
              const SizedBox(height: 20),
              Text('Tus canciones top', style: theme.textTheme.titleMedium),
              if (top.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Todavía no hay suficiente información. Escucha música con '
                      'SmartBuds activo y di «me gusta» cuando algo te encante.'),
                ),
              for (final t in top)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.music_note),
                  title: Text(t.title),
                  subtitle: Text(t.artist ?? ''),
                  trailing: Text(t.score(profile.weights).toStringAsFixed(0)),
                ),
              if (artists.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Tus artistas', style: theme.textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: [for (final (a, _) in artists) Chip(label: Text(a))],
                ),
              ],
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
