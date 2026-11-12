import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'social_service.dart';
import 'listen_party.dart';
import 'achievements.dart';

/// Amigos: tu perfil, canciones que te envían, amigos (compatibilidad y
/// descubrimientos), listas compartidas y el resumen del grupo.
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key, required this.assistant, this.social, this.party});

  /// Escucha sincronizada (null si no hay cuenta configurada).
  final ListenParty? party;

  final Assistant assistant;

  /// Null si la app no tiene Supabase configurado.
  final SocialService? social;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  SocialService? get social => widget.social;
  Assistant get assistant => widget.assistant;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _ask(String title, {String hint = '', String initial = '', TextCapitalization caps = TextCapitalization.none}) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: caps,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (t) => Navigator.pop(c, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Listo')),
        ],
      ),
    );
    ctrl.dispose();
    return (v ?? '').trim().isEmpty ? null : v!.trim();
  }

  List<String> get _myTop => assistant.profile.topArtists(15).map((e) => e.$1).toList();

  @override
  Widget build(BuildContext context) {
    final s = social;
    final settings = assistant.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
        actions: [
          if (s != null && (settings?.signedIn ?? false))
            IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: s.refresh),
        ],
      ),
      body: s == null || settings == null
          ? const _Empty('Amigos necesita la cuenta de SmartBuds (Supabase), que no está activa en esta versión.')
          : ListenableBuilder(
              listenable: Listenable.merge([s, settings, if (widget.party != null) widget.party!]),
              builder: (context, _) {
                if (!settings.signedIn) {
                  return const _Empty('Entra con tu cuenta en «Mi música» para compartir música con tus amigos.');
                }
                return RefreshIndicator(
                  onRefresh: s.refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 40),
                    children: [
                      if (s.loading) const LinearProgressIndicator(),
                      if (s.error != null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.error_outline, color: Neon.pink),
                            title: Text(s.error!),
                          ),
                        ),
                      _profileCard(s),
                      if (s.profile != null) ...[
                        if (widget.party != null) _party(widget.party!, s),
                        _inbox(s),
                        _friends(s),
                        _trends(s),
                        _playlists(s),
                        _group(s),
                      ],
                      _achievements(s),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // ------------------------------------------------------------ Perfil

  Widget _profileCard(SocialService s) {
    final theme = Theme.of(context);
    final p = s.profile;
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIcon(Icons.person_rounded, colors: AppColors.radio, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p?.name ?? 'Crea tu perfil', style: theme.textTheme.titleLarge),
                    Text(
                      p == null
                          ? 'Solo un nombre y tus artistas favoritos. Nunca tu historial.'
                          : 'Tu código de amigo: ${p.friendCode}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (p == null)
            FilledButton.icon(
              onPressed: () async {
                final name = await _ask('¿Cómo te verán tus amigos?', hint: 'Tu nombre', caps: TextCapitalization.words);
                if (name == null) return;
                if (await s.saveProfile(name, isPublic: false, topArtists: _myTop)) _snack('¡Listo! Ya tienes código de amigo.');
              },
              icon: const Icon(Icons.add),
              label: const Text('Crear mi perfil'),
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Perfil público'),
              subtitle: const Text('Otros pueden ver tu nombre y artistas favoritos. Apagado: solo con tu código.'),
              value: p.isPublic,
              onChanged: (v) => s.saveProfile(p.name, isPublic: v, topArtists: _myTop),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final text = 'Agrégame en SmartBuds AI → Amigos. Mi código: ${p.friendCode}';
                    final ok = await assistant.media?.shareText(text) ?? false;
                    if (!ok) {
                      await Clipboard.setData(ClipboardData(text: p.friendCode));
                      _snack('Código copiado.');
                    }
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Compartir mi código'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    if (await s.saveProfile(p.name, isPublic: p.isPublic, topArtists: _myTop)) {
                      _snack('Tus artistas favoritos quedaron al día.');
                    }
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Actualizar mis artistas'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------- Escuchar juntos

  Widget _party(ListenParty party, SocialService s) {
    final room = party.room;
    return _Section(
      title: 'Escuchar juntos',
      icon: Icons.headset_mic_rounded,
      children: [
        if (room == null) ...[
          const ListTile(
            dense: true,
            title: Text('Escuchen la misma canción al tiempo, cada quien en su app y con su cuenta. '
                'Solo pueden unirse amigos mutuos con el código.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: party.host,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Abrir mi sala'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final code = await _ask('Código de la sala', hint: 'Ej.: A2B6630E', caps: TextCapitalization.characters);
                    if (code == null) return;
                    if (await party.join(code)) _snack('¡Te uniste! Tu app va a seguir la música del anfitrión.');
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Unirme con código'),
                ),
              ],
            ),
          ),
        ] else ...[
          ListTile(
            leading: NeonEqualizer(playing: room.playing, height: 22),
            title: Text(room.isHost ? 'Tu sala · código ${room.code}' : 'En la sala de un amigo'),
            subtitle: Text(party.status ?? ''),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              children: [
                if (room.isHost)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final text = 'Escucha conmigo en SmartBuds AI → Amigos → Escuchar juntos. Código: ${room.code}';
                      final ok = await assistant.media?.shareText(text) ?? false;
                      if (!ok) await Clipboard.setData(ClipboardData(text: room.code));
                    },
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Invitar'),
                  ),
                TextButton.icon(
                  onPressed: party.leave,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(room.isHost ? 'Cerrar la sala' : 'Salir'),
                ),
              ],
            ),
          ),
        ],
        if (party.status == 'La sala se cerró.')
          const ListTile(dense: true, leading: Icon(Icons.info_outline), title: Text('La sala se cerró.')),
      ],
    );
  }

  // --------------------------------------------------------- Tendencias

  Widget _trends(SocialService s) {
    if (s.contacts.where((c) => c.mutual).length < 2) return const SizedBox.shrink();
    return _Section(
      title: 'Tendencias de tu círculo',
      icon: Icons.local_fire_department_rounded,
      children: [
        FutureBuilder<List<(String, int)>>(
          future: s.circleTrends(),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return const ListTile(
                dense: true,
                title: Text('Cuando 2 o más amigos compartan un artista favorito, aparecerá aquí '
                    '(sin decir quiénes).'),
              );
            }
            return Column(
              children: [
                for (final (artist, n) in list)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.trending_up_rounded, color: Neon.cyan),
                    title: Text(artist),
                    subtitle: Text('Favorito de $n de tus amigos'),
                    trailing: const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan),
                    onTap: () => assistant.handleSearch(SearchRequest(artist)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // -------------------------------------------------- Insignias y desafíos

  Widget _achievements(SocialService s) {
    final settings = assistant.settings;
    if (settings == null) return const SizedBox.shrink();
    final a = Achievements(assistant.profile, settings);
    final badges = a.badges(mutualFriends: s.contacts.where((c) => c.mutual).length);
    final theme = Theme.of(context);
    return _Section(
      title: 'Insignias y desafíos',
      icon: Icons.emoji_events_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(alignment: Alignment.centerLeft, child: Text('Desafíos de esta semana', style: theme.textTheme.titleSmall)),
        ),
        for (final c in a.weekly())
          ListTile(
            dense: true,
            leading: Icon(c.done ? Icons.check_circle_rounded : Icons.flag_outlined, color: c.done ? Colors.green : Neon.cyan),
            title: Text(c.title),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: (c.progress / c.goal).clamp(0.0, 1.0).toDouble(), minHeight: 5),
            ),
            trailing: Text('${c.progress.clamp(0, c.goal)}/${c.goal}'),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in badges)
                Tooltip(
                  message: '${b.description} (${b.progress.clamp(0, b.goal)}/${b.goal})',
                  child: Chip(
                    avatar: Icon(b.earned ? Icons.military_tech_rounded : Icons.lock_outline_rounded,
                        size: 18, color: b.earned ? Neon.cyan : null),
                    label: Text(b.title),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Bandeja

  Widget _inbox(SocialService s) {
    return _Section(
      title: 'Te enviaron',
      icon: Icons.inbox_rounded,
      trailing: s.unseen > 0
          ? TextButton(onPressed: s.markInboxSeen, child: Text('Marcar ${s.unseen} como vistas'))
          : null,
      children: [
        if (s.inbox.isEmpty)
          const ListTile(dense: true, title: Text('Aún nadie te ha enviado canciones.')),
        for (final song in s.inbox.take(15))
          ListTile(
            leading: Icon(song.seen ? Icons.music_note_outlined : Icons.fiber_new_rounded,
                color: song.seen ? null : Neon.pink),
            title: Text([song.title, if ((song.artist ?? '').isNotEmpty) song.artist].join(' — ')),
            subtitle: Text([
              song.fromName == null ? 'De alguien anónimo' : 'De ${song.fromName}',
              if ((song.message ?? '').isNotEmpty) '«${song.message}»',
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Escuchar',
              icon: const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan, size: 32),
              onPressed: () => assistant.handleSearch(
                  SearchRequest([song.title, if ((song.artist ?? '').isNotEmpty) song.artist].join(' '))),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ Amigos

  Widget _friends(SocialService s) {
    return _Section(
      title: 'Tus amigos',
      icon: Icons.group_rounded,
      trailing: TextButton.icon(
        onPressed: () async {
          final code = await _ask('Código de tu amigo', hint: 'Ej.: K7M2QX', caps: TextCapitalization.characters);
          if (code == null) return;
          final r = await s.addContact(code);
          if (r == null) return;
          _snack(r.mutual
              ? '¡${r.name} y tú ya son amigos! Pueden enviarse canciones.'
              : 'Agregaste a ${r.name}. Cuando te agregue también, podrán enviarse canciones.');
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Agregar'),
      ),
      children: [
        if (s.contacts.isEmpty)
          const ListTile(
            dense: true,
            title: Text('Agrega amigos con su código. Cuando los dos se agreguen, podrán enviarse canciones.'),
          ),
        for (final f in s.contacts)
          ListTile(
            leading: CircleAvatar(child: Text(f.name.isEmpty ? '?' : f.name[0].toUpperCase())),
            title: Text(f.name),
            subtitle: Text(f.mutual ? 'Amigos · código ${f.code}' : 'Pendiente: falta que te agregue'),
            onTap: () => _friendSheet(s, f),
            trailing: Icon(f.mutual ? Icons.chevron_right : Icons.hourglass_top_rounded),
          ),
      ],
    );
  }

  Future<void> _friendSheet(SocialService s, Contact f) async {
    final c = assistant.profile.compareArtists(f.topArtists);
    final discover = assistant.profile.newFromFriend(f.topArtists);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (!f.mutual)
                  Text('${f.name} aún no te ha agregado. Pásale tu código para que puedan '
                      'compararse y enviarse canciones.')
                else ...[
                  // Compatibilidad musical.
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: c.percent / 100,
                              strokeWidth: 6,
                              color: Neon.cyan,
                              backgroundColor: Neon.ink.withValues(alpha: .1),
                            ),
                            Text('${c.percent}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(c.shared.isEmpty
                            ? 'No tienen artistas en común… ¡aún!'
                            : 'En común: ${c.shared.join(', ')}'),
                      ),
                    ],
                  ),
                  if (discover.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Descubre por ${f.name}', style: theme.textTheme.titleSmall),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final a in discover.take(6))
                          ActionChip(
                            avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text(a),
                            onPressed: () {
                              Navigator.pop(context);
                              assistant.handleSearch(SearchRequest(a));
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _sendTo(s, f.userId, f.name);
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Enviarle una canción'),
                  ),
                ],
                TextButton(
                  onPressed: () {
                    s.removeContact(f.userId);
                    Navigator.pop(context);
                  },
                  child: const Text('Quitar de mis amigos (deja de recibir sus canciones nuevas)'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendTo(SocialService s, String userId, String name) async {
    final a = assistant.active;
    final title = TextEditingController(text: a?.title ?? '');
    final artist = TextEditingController(text: a?.artist ?? '');
    final msg = TextEditingController();
    var anonymous = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Enviar a $name'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Canción')),
                const SizedBox(height: 8),
                TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artista')),
                const SizedBox(height: 8),
                TextField(controller: msg, maxLength: 200, decoration: const InputDecoration(labelText: 'Mensaje (opcional)')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enviar anónima'),
                  subtitle: const Text('No verá quién se la envió.'),
                  value: anonymous,
                  onChanged: (v) => set(() => anonymous = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      final sent = await s.sendSong(
        toUserId: userId,
        title: title.text.trim(),
        artist: artist.text.trim().isEmpty ? null : artist.text.trim(),
        message: msg.text,
        anonymous: anonymous,
      );
      if (sent) _snack('Canción enviada a $name.');
    }
    title.dispose();
    artist.dispose();
    msg.dispose();
  }

  // ---------------------------------------------------- Listas compartidas

  Widget _playlists(SocialService s) {
    return _Section(
      title: 'Listas compartidas',
      icon: Icons.queue_music_rounded,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.add_circle_outline_rounded),
        onSelected: (v) async {
          if (v == 'new') {
            final name = await _ask('Nombre de la lista', hint: 'Ej.: Viaje a la costa', caps: TextCapitalization.sentences);
            if (name == null) return;
            final p = await s.createPlaylist(name);
            if (p != null) _snack('Lista creada. Invita con el código ${p.inviteCode}.');
          } else {
            final code = await _ask('Código de invitación', hint: 'Ej.: 3FA9C2D1', caps: TextCapitalization.characters);
            if (code == null) return;
            final p = await s.joinPlaylist(code);
            if (p != null) _snack('Te uniste a «${p.name}».');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'new', child: Text('Crear una lista')),
          PopupMenuItem(value: 'join', child: Text('Unirme con un código')),
        ],
      ),
      children: [
        if (s.playlists.isEmpty)
          const ListTile(dense: true, title: Text('Crea una lista y tus amigos agregan canciones con el código.')),
        for (final p in s.playlists)
          ListTile(
            leading: const AppIcon(Icons.queue_music_rounded, colors: AppColors.music, size: 36),
            title: Text(p.name),
            subtitle: Text('Código ${p.inviteCode}${p.isMine ? ' · tuya' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPlaylist(s, p),
          ),
      ],
    );
  }

  Future<void> _openPlaylist(SocialService s, SharedPlaylist p) async {
    var items = await s.items(p.id);
    var votes = await s.scores(p.id);
    List<PlaylistItem> sorted() =>
        [...items]..sort((a, b) => (votes[b.id]?.score ?? 0).compareTo(votes[a.id]?.score ?? 0));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, set) {
          final theme = Theme.of(context);
          Future<void> reload() async {
            final fresh = await s.items(p.id);
            final v = await s.scores(p.id);
            set(() {
              items = fresh;
              votes = v;
            });
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                    child: Row(
                      children: [
                        Expanded(child: Text(p.name, style: theme.textTheme.titleLarge)),
                        IconButton(
                          tooltip: 'Invitar',
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          onPressed: () async {
                            final text = 'Únete a mi lista «${p.name}» en SmartBuds AI → Amigos. Código: ${p.inviteCode}';
                            final ok = await assistant.media?.shareText(text) ?? false;
                            if (!ok) await Clipboard.setData(ClipboardData(text: p.inviteCode));
                          },
                        ),
                        if (p.isMine)
                          IconButton(
                            tooltip: 'Cambiar código de invitación',
                            icon: const Icon(Icons.key_rounded),
                            onPressed: () async {
                              final c = await s.rotateInvite(p);
                              if (c != null) _snack('Nuevo código: $c. El anterior ya no sirve.');
                            },
                          ),
                        IconButton(
                          tooltip: p.isMine ? 'Borrar lista' : 'Salir de la lista',
                          icon: const Icon(Icons.logout_rounded),
                          onPressed: () async {
                            Navigator.pop(context);
                            await s.leavePlaylist(p);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if ((assistant.active?.title ?? '').isNotEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Agregar la que suena'),
                            onPressed: () async {
                              final a = assistant.active!;
                              if (await s.addItem(p.id, a.title!, a.artist)) await reload();
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.edit, size: 18),
                          label: const Text('Escribir una'),
                          onPressed: () async {
                            final t = await _ask('Canción (y artista)', hint: 'Ojalá - Ryan Castro');
                            if (t == null) return;
                            final parts = t.split(' - ');
                            if (await s.addItem(p.id, parts.first.trim(), parts.length > 1 ? parts[1].trim() : null)) {
                              await reload();
                            }
                          },
                        ),
                        if (items.isNotEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.how_to_vote_rounded, size: 18),
                            label: const Text('Poner la más votada'),
                            onPressed: () {
                              Navigator.pop(context);
                              final top = sorted().first;
                              assistant.handleSearch(
                                  SearchRequest([top.title, if ((top.artist ?? '').isNotEmpty) top.artist].join(' ')));
                            },
                          ),
                        if (items.isNotEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.playlist_play_rounded, size: 18),
                            label: const Text('Ponerla toda'),
                            onPressed: () {
                              Navigator.pop(context);
                              String q(PlaylistItem i) => [i.title, if ((i.artist ?? '').isNotEmpty) i.artist].join(' ');
                              final order = sorted(); // las más votadas primero
                              assistant.queue
                                ..clear()
                                ..addAll(order.skip(1).map(q));
                              assistant.handleSearch(SearchRequest(q(order.first)));
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('La lista está vacía. ¡Agrega la primera!'))
                        : ListView(
                            children: [
                              for (final i in sorted())
                                ListTile(
                                  leading: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () async {
                                          await s.vote(i.id, votes[i.id]?.mine == 1 ? 0 : 1);
                                          await reload();
                                        },
                                        child: Icon(Icons.thumb_up_alt_rounded,
                                            size: 18, color: votes[i.id]?.mine == 1 ? Neon.cyan : null),
                                      ),
                                      Text('${votes[i.id]?.score ?? 0}', style: const TextStyle(fontSize: 12)),
                                      InkWell(
                                        onTap: () async {
                                          await s.vote(i.id, votes[i.id]?.mine == -1 ? 0 : -1);
                                          await reload();
                                        },
                                        child: Icon(Icons.thumb_down_alt_rounded,
                                            size: 18, color: votes[i.id]?.mine == -1 ? Neon.pink : null),
                                      ),
                                    ],
                                  ),
                                  title: Text(i.title),
                                  subtitle: Text([
                                    if ((i.artist ?? '').isNotEmpty) i.artist!,
                                    if (i.addedBy != null) 'agregó ${i.addedBy}',
                                  ].join(' · ')),
                                  onTap: () => assistant.handleSearch(
                                      SearchRequest([i.title, if ((i.artist ?? '').isNotEmpty) i.artist].join(' '))),
                                  trailing: i.mine
                                      ? IconButton(
                                          tooltip: 'Quitar',
                                          icon: const Icon(Icons.close),
                                          onPressed: () async {
                                            await s.removeItem(i.id);
                                            await reload();
                                          },
                                        )
                                      : null,
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

  // ------------------------------------------------------- Resumen grupo

  Widget _group(SocialService s) {
    if (s.playlists.isEmpty && s.inbox.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Resumen del grupo',
      icon: Icons.insights_rounded,
      children: [
        FutureBuilder(
          future: s.groupSummary(),
          builder: (context, snap) {
            final d = snap.data;
            if (d == null) {
              return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            }
            if (d.artists.isEmpty && d.songs.isEmpty) {
              return const ListTile(dense: true, title: Text('Cuando agreguen canciones verás lo más compartido.'));
            }
            return Column(
              children: [
                for (final (a, n) in d.artists)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(a),
                    trailing: Text('$n'),
                    onTap: () => assistant.handleSearch(SearchRequest(a)),
                  ),
                if (d.songs.isNotEmpty) const Divider(),
                for (final (t, n) in d.songs)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.music_note_outlined),
                    title: Text(t),
                    trailing: Text('$n'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children, this.trailing});
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 0, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.3, color: theme.colorScheme.primary)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(Icons.group_rounded, colors: AppColors.radio, size: 64),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
