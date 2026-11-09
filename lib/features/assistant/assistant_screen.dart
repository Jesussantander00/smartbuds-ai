import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import 'assistant.dart';

/// Asistente: qué puedes decir y cómo responde SmartBuds.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.settings,
    this.voice,
    this.onHeadphoneTapsChanged,
    this.assistant,
  });

  /// Para los ajustes que hablan con el teléfono (llamadas, audífonos).
  final Assistant? assistant;

  final AppSettings settings;
  final VoiceEngine? voice;

  /// Avisa al lado nativo (Android) de que se activaron/desactivaron los toques.
  final ValueChanged<bool>? onHeadphoneTapsChanged;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  AppSettings get settings => widget.settings;
  VoiceEngine? get voice => widget.voice;
  bool _speakerAvailable = false;
  String _filter = '';
  bool _allHistory = false;

  @override
  void initState() {
    super.initState();
    voice?.speakerAvailable().then((v) {
      if (mounted) setState(() => _speakerAvailable = v);
    });
  }

  static const _commands = <(String, String)>[
    ('«Cambia»', 'Siguiente canción'),
    ('«Devuelve»', 'Canción anterior'),
    ('«Pausa» / «Continúa»', 'Pausar o seguir'),
    ('«Sube» / «Baja»', 'Volumen'),
    ('«Busca»', 'Te pregunta «¿Qué canción?» y la reproduce'),
    ('«Oye música»', 'Responde «¿Sí?»: di lo que quieras, p. ej. «busca Ojalá de Ryan Castro»'),
    ('«Me gusta»', 'Guarda la canción en tus favoritas'),
    ('«No me gusta»', 'La baja en tu perfil y la cambia'),
    ('«Pon algo que me guste»', 'Elige una de tus favoritas según la hora'),
    ('«Pon algo nuevo»', 'Canciones que no conoces de tus artistas'),
    ('«Pon algo de»', 'Te pregunta «¿De quién?» y pone música de ese artista'),
    ('«Pon algo para entrenar»', 'También: tranquilo, de fiesta, para dormir, para estudiar'),
    ('«Pon …» (sin música)', 'Si no suena nada: «pon Ojalá de Ryan Castro» directo'),
    ('«¿Qué suena?»', 'Te dice el nombre de la canción'),
    ('«Repite» / «Otra vez»', 'La canción desde el principio'),
    ('«Adelanta» / «Atrasa»', '30 segundos adelante o atrás'),
    ('«Apaga en veinte minutos»', 'Temporizador: baja el volumen y pausa. «Cancela el temporizador»'),
    ('«Deshacer»', 'Vuelve a la canción de antes, donde iba'),
    ('«Comparte esta»', 'Prepara el enlace para WhatsApp'),
    ('«Pon mi radio»', 'Música sin parar: favoritas y descubrimientos'),
    ('«Volumen al cincuenta»', 'Volumen exacto. También «al máximo», «a la mitad»'),
    ('«Después pon …»', 'La pone cuando termine la actual (cola)'),
    ('«La que dice …»', 'Busca por un pedazo de la letra'),
    ('«Cambia y sube»', 'Varias órdenes en una frase'),
    ('«Nunca más esta»', 'No vuelve a sonar. «Nunca más este artista» bloquea al artista'),
    ('«Pon favoritas olvidadas»', 'Lo que te encantaba y hace rato no suena'),
    ('«Comparte mi semana»', 'Tu resumen musical para WhatsApp'),
    ('«Pon media hora de música»', 'Una lista de tus canciones para ese tiempo'),
    ('«Busca música de los ochenta»', 'Por época: sesenta, setenta, ochenta, noventa, dos mil'),
    ('«Busca la versión acústica de …»', 'También «en vivo», «remix», «original», «instrumental»'),
    ('«Busca una canción tranquila con guitarra»', 'Busca por descripción'),
    ('«Pon algo parecido»', 'Una canción de un artista parecido al que suena'),
    ('«¿Por qué esta?»', 'Te dice qué sabe SmartBuds de la canción que suena'),
  ];

  Future<void> _editWake(BuildContext context) async {
    final settings = widget.settings;
    final ctrl = TextEditingController(text: settings.wakePhrase);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tu palabra de activación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Usa dos palabras comunes en español, por ejemplo «hola amigo» '
                'u «oye parce». Nombres raros o en inglés pueden no reconocerse.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'hola amigo',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Quitar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null) return;
    settings.update(wakePhrase: value);
    await widget.voice?.setCustomWake(value);
  }

  bool _match(String a, [String b = '']) {
    if (_filter.isEmpty) return true;
    final f = _filter.toLowerCase();
    return a.toLowerCase().contains(f) || b.toLowerCase().contains(f);
  }

  /// Un interruptor que se oculta si no coincide con la búsqueda.
  Widget? _switch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    if (!_match(title, subtitle)) return null;
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  /// Sección con título; desaparece si ningún ajuste coincide.
  List<Widget> _section(BuildContext context, String title, IconData icon, List<Widget?> items) {
    final visible = items.whereType<Widget>().toList();
    if (visible.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title.toUpperCase(),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(letterSpacing: 1.3, color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
      Card(child: Column(children: visible)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.assistant?.media;
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, if (voice != null) voice!]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 120),
          children: [
            if (voice != null && _filter.isEmpty) _hero(context, voice!),
            if (widget.assistant != null && _filter.isEmpty) _quick(context),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar un ajuste u orden…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (voice != null && _filter.isEmpty) ..._history(context, voice!),
            ..._section(context, 'Lo que puedes decir', Icons.record_voice_over, [
              if (_filter.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text('Di la orden sola, con una pequeña pausa antes y después. '
                      'Hablar o cantar normal no dispara nada.'),
                ),
              for (final (say, does) in _commands)
                if (_match(say, does)) ListTile(dense: true, title: Text(say), subtitle: Text(does)),
            ]),
            ..._section(context, 'Voz y escucha', Icons.mic, [
              _switch('Respuesta por voz', 'SmartBuds te confirma al oído: «Reproduciendo…»',
                  settings.voiceFeedback, (v) {
                settings.update(voiceFeedback: v);
                voice?.feedbackEnabled = v;
              }),
              _switch('Respuestas cortas', 'Solo lo esencial: una frase por respuesta.',
                  settings.shortReplies, (v) {
                settings.update(shortReplies: v);
                voice?.shortReplies = v;
              }),
              _switch('Solo con «Oye música»',
                  'Solo obedece después de «Oye música». Casi nunca se activa por error.',
                  settings.wakeWord, (v) {
                settings.update(wakeWord: v);
                voice?.requireWakeWord = v;
              }),
              if (_match('Tu palabra de activación', 'oye música'))
                ListTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('Tu palabra de activación'),
                  subtitle: Text(settings.wakePhrase.isEmpty
                      ? 'Además de «Oye música». Toca para elegir una.'
                      : '«${settings.wakePhrase}» (y también «Oye música»)'),
                  onTap: () => _editWake(context),
                ),
              if (voice != null && _match('Probar la voz de SmartBuds'))
                ListTile(
                  leading: const Icon(Icons.volume_up),
                  title: const Text('Probar la voz de SmartBuds'),
                  onTap: () => voice!.speak('Hola, soy SmartBuds. Dime qué quieres escuchar.',
                      force: true),
                ),
            ]),
            ..._section(context, 'Música', Icons.library_music, [
              _switch('Radio SmartBuds', 'Cuando termina una canción, SmartBuds elige la siguiente.',
                  settings.radioMode, (v) => settings.update(radioMode: v)),
              _switch('Anunciar cada canción', 'Dice suavemente el nombre de la canción nueva.',
                  settings.announceSongs, (v) => settings.update(announceSongs: v)),
              _switch('Descubrimiento gradual',
                  'La radio empieza con tus conocidas y va metiendo más canciones nuevas.',
                  settings.gradualDiscovery, (v) => settings.update(gradualDiscovery: v)),
              if (_match('Nivel de descubrimiento', 'joyas ocultas conocidos'))
                ListTile(
                  title: const Text('Nivel de descubrimiento'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Conocidos')),
                        ButtonSegment(value: 1, label: Text('Mixto')),
                        ButtonSegment(value: 2, label: Text('Joyas ocultas')),
                      ],
                      selected: {settings.discoveryLevel},
                      onSelectionChanged: (v) => settings.update(discoveryLevel: v.first),
                    ),
                  ),
                ),
              _switch('Sugerencias según el clima',
                  'Usa tu ubicación aproximada (por internet, sin GPS) para sugerir música.',
                  settings.weatherSuggestions, (v) {
                settings.update(weatherSuggestions: v);
                widget.assistant?.refreshWeather();
              }),
              if (_match('Bloqueadas', 'nunca más'))
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Bloqueadas («Nunca más»)'),
                  subtitle: Text(
                      '${settings.blockedTracks.length} canciones · ${settings.blockedArtists.length} artistas'),
                  onTap: () => _showBlocked(context),
                ),
            ]),
            ..._section(context, 'Audífonos y llamadas', Icons.headphones, [
              _switch('Seguir a mis audífonos',
                  'Pausa la escucha al quitarte los audífonos y la reanuda al conectarlos',
                  settings.followHeadphones, (v) {
                settings.update(followHeadphones: v);
                voice?.followHeadphones = v;
              }),
              _switch('Pausar al quitar los audífonos', 'La música se detiene sola al desconectarlos.',
                  settings.pauseOnUnplug, (v) {
                settings.update(pauseOnUnplug: v);
                media?.setPauseOnUnplug(v);
              }),
              _switch('Retomar al conectar audífonos', 'La música sigue donde la dejaste.',
                  settings.resumeOnHeadphones, (v) => settings.update(resumeOnHeadphones: v)),
              _switch('Pausar en llamadas', 'Pausa al entrar una llamada y sigue al colgar.',
                  settings.pauseOnCalls, (v) {
                settings.update(pauseOnCalls: v);
                media?.setCallPause(v);
              }),
              _switch('Toques en los audífonos',
                  'Dos toques: siguiente canción. Tres toques: la anterior.',
                  settings.headphoneTaps, (v) {
                settings.update(headphoneTaps: v);
                widget.onHeadphoneTapsChanged?.call(v);
              }),
              if (settings.headphoneVolumes.isNotEmpty && _match('Volumen por audífono'))
                for (final e in settings.headphoneVolumes.entries)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.headset),
                    title: Text(e.key),
                    subtitle: Text('Volumen preferido: ${e.value} %'),
                  ),
            ]),
            ..._section(context, 'Batería y privacidad', Icons.battery_saver, [
              _switch('Ahorro de batería',
                  'Con menos de 20 %: respuestas cortas, sin anuncios ni sugerencias por internet.',
                  settings.batterySaver, (v) {
                settings.update(batterySaver: v);
                widget.assistant?.checkBattery();
              }),
              _switch('Enviar reportes de errores',
                  'Anónimos: solo el tipo de error, nunca tu voz ni lo que dices.',
                  settings.errorReports, (v) => settings.update(errorReports: v)),
              if (_match('Con la pantalla apagada', 'notificación'))
                const ListTile(
                  leading: Icon(Icons.screen_lock_portrait),
                  title: Text('Con la pantalla apagada'),
                  subtitle: Text('Mientras el micrófono esté activo verás la notificación con '
                      '⏮ ⏯ ⏭. Puedes bloquear el teléfono: sigue escuchando hasta que toques '
                      '«Detener».'),
                ),
            ]),
            ..._section(context, 'Apariencia', Icons.palette, [
              if (_match('Apariencia', 'tema oscuro claro color'))
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'light', label: Text('Claro'), icon: Icon(Icons.light_mode)),
                          ButtonSegment(value: 'dark', label: Text('Oscuro'), icon: Icon(Icons.dark_mode)),
                          ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (v) => settings.update(themeMode: v.first),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final c in const [0xFFE8833A, 0xFF2F6FE4, 0xFF7C4DFF, 0xFFE5484D, 0xFF1FA889])
                            GestureDetector(
                              onTap: () => settings.update(seedColor: c),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(c),
                                child: settings.seedColor == c
                                    ? const Icon(Icons.check, color: Colors.white)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ]),
            if (voice != null && _match('Solo mi voz', 'entrenar')) ...[
              const SizedBox(height: 16),
              _onlyMyVoice(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Micrófono central, lo que oyó y la respuesta de SmartBuds en una burbuja.
  Widget _hero(BuildContext context, VoiceEngine v) {
    final theme = Theme.of(context);
    final last = v.history.isEmpty ? null : v.history.first;
    final state = !v.enabled
        ? 'Micrófono apagado'
        : v.askingForSong
            ? 'Te escucho…'
            : v.paused
                ? 'En pausa (sin audífonos)'
                : v.listening
                    ? 'Escuchando'
                    : 'Preparando…';
    return Column(
      children: [
        const SizedBox(height: 8),
        MicOrb(
          size: 170,
          on: v.enabled,
          listening: v.listening && !v.paused,
          onTap: v.toggle,
          icon: v.enabled ? (v.paused ? Icons.mic_off : Icons.mic) : Icons.mic_none,
        ),
        const SizedBox(height: 4),
        Text(state,
            style: theme.textTheme.titleMedium?.copyWith(
                color: v.enabled && v.listening ? const Color(0xFFB9762A) : null, fontWeight: FontWeight.w600)),
        if (v.lastHeard.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('«${v.lastHeard}»',
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ),
        if (last?.reply != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: Neon.cyan.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: Neon.cyan),
                const SizedBox(width: 8),
                Flexible(child: Text(last!.reply!)),
              ],
            ),
          ),
        if (v.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(v.error!,
                textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }

  static const _quickCommands = <(IconData, String, String)>[
    (Icons.music_note, '¿Qué suena?', 'que suena'),
    (Icons.favorite, 'Mis favoritas', 'pon mis favoritas'),
    (Icons.explore, 'Algo nuevo', 'pon algo nuevo'),
    (Icons.radio, 'Mi radio', 'pon mi radio'),
    (Icons.history_toggle_off, 'Olvidadas', 'pon favoritas olvidadas'),
    (Icons.bedtime, 'Apagar en 30 min', 'apaga en treinta minutos'),
  ];

  /// Comandos frecuentes a un toque.
  Widget _quick(BuildContext context) {
    const parser = CommandParser();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (icon, label, phrase) in _quickCommands)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  onPressed: () {
                    final intent = parser.parseIntent(phrase);
                    if (intent != null) widget.assistant?.handleIntent(intent);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Historial de voz: lo que dijiste y lo que hizo SmartBuds.
  List<Widget> _history(BuildContext context, VoiceEngine v) {
    final theme = Theme.of(context);
    final items = _allHistory ? v.history : v.history.take(5).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('HISTORIAL DE VOZ',
                style: theme.textTheme.labelLarge
                    ?.copyWith(letterSpacing: 1.3, color: theme.colorScheme.primary)),
          ],
        ),
      ),
      Card(
        child: v.history.isEmpty
            ? const ListTile(
                leading: Icon(Icons.mic_none),
                title: Text('Aún no hay órdenes'),
                subtitle: Text('Lo que le digas a SmartBuds aparecerá aquí.'),
              )
            : Column(
                children: [
                  for (final e in items)
                    ListTile(
                      dense: true,
                      leading: Icon(_iconFor(e.action), color: Neon.cyan),
                      trailing: Text(TimeOfDay.fromDateTime(e.at).format(context),
                          style: theme.textTheme.labelSmall),
                      title: Text(e.action),
                      subtitle: Text([
                        if (e.heard.isNotEmpty) 'Oí: «${e.heard}»',
                        if (e.reply != null) 'Dijo: «${e.reply}»',
                      ].join('\n')),
                    ),
                  if (v.history.length > 5)
                    TextButton(
                      onPressed: () => setState(() => _allHistory = !_allHistory),
                      child: Text(_allHistory ? 'Ver menos' : 'Ver todo (${v.history.length})'),
                    ),
                ],
              ),
      ),
    ];
  }

  static IconData _iconFor(String action) {
    final a = action.toLowerCase();
    if (a.startsWith('buscar') || a.startsWith('letra')) return Icons.search;
    if (a.contains('siguiente') || a.contains('anterior')) return Icons.skip_next;
    if (a.contains('volumen')) return Icons.volume_up;
    if (a.contains('pausa') || a.contains('continuar')) return Icons.play_arrow;
    if (a.contains('gusta') || a.contains('favorit')) return Icons.favorite;
    if (a.contains('bloquear') || a.contains('nunca')) return Icons.block;
    if (a.contains('después') || a.contains('cola')) return Icons.queue_music;
    if (a.contains('apagar') || a.contains('temporizador')) return Icons.bedtime;
    if (a.contains('compartir')) return Icons.ios_share;
    if (a.contains('radio')) return Icons.radio;
    return Icons.record_voice_over;
  }

  Future<void> _showBlocked(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final tracks = settings.blockedTracks.toList()..sort();
          final artists = settings.blockedArtists.toList()..sort();
          if (tracks.isEmpty && artists.isEmpty) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('No hay nada bloqueado.')),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final a in artists)
                ListTile(
                  leading: const Icon(Icons.person_off),
                  title: Text(a),
                  subtitle: const Text('Artista'),
                  trailing: TextButton(
                      onPressed: () => settings.unblock(a, artist: true),
                      child: const Text('Desbloquear')),
                ),
              for (final t in tracks)
                ListTile(
                  leading: const Icon(Icons.music_off),
                  title: Text(t.split('|').first),
                  subtitle: Text(t.split('|').last),
                  trailing: TextButton(
                      onPressed: () => settings.unblock(t), child: const Text('Desbloquear')),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _onlyMyVoice(BuildContext context) {
    final v = voice!;
    final theme = Theme.of(context);
    if (!_speakerAvailable) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.person_off),
          title: Text('Solo mi voz (no disponible)'),
          subtitle: Text('Ejecuta otra vez scripts/descargar-modelo-voz.ps1 (ahora incluye '
              'el modelo de hablante) y reinstala la app.'),
        ),
      );
    }
    final trained = settings.voiceprint != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solo mi voz', style: theme.textTheme.titleMedium),
            const Text('SmartBuds aprende cómo suena tu voz y no obedece a otras personas.'),
            const SizedBox(height: 8),
            if (v.enrolling)
              ListTile(
                leading: const CircularProgressIndicator(),
                title: Text('Di «Cambia» (${v.enrollCount + 1} de ${VoiceEngine.enrollTarget})'),
                subtitle: const Text('Con tu tono normal, como le hablarías a SmartBuds.'),
                trailing: TextButton(
                    onPressed: v.cancelEnrollment, child: const Text('Cancelar')),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  if (!v.enabled) await v.start();
                  if (!v.enabled) return;
                  v.startEnrollment((print) {
                    settings.update(voiceprint: print, onlyMyVoice: true);
                    v.guard.enabled = true;
                  });
                  await v.speak('Di cambia tres veces.', force: true);
                },
                icon: const Icon(Icons.record_voice_over),
                label: Text(trained ? 'Volver a entrenar mi voz' : 'Entrenar mi voz'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo responder a mi voz'),
              subtitle: Text(trained ? 'Voz entrenada' : 'Primero entrena tu voz'),
              value: settings.onlyMyVoice && trained,
              onChanged: trained
                  ? (on) {
                      settings.update(onlyMyVoice: on);
                      v.guard.enabled = on;
                    }
                  : null,
            ),
            if (trained) ...[
              Text('Exigencia: ${(settings.voiceThreshold * 100).round()} %',
                  style: theme.textTheme.bodySmall),
              Slider(
                min: 0.3,
                max: 0.8,
                divisions: 10,
                value: settings.voiceThreshold.clamp(0.3, 0.8),
                onChanged: (x) {
                  settings.update(voiceThreshold: x);
                  v.guard.threshold = x;
                },
              ),
              const Text('Si a veces no te obedece, bájala. Si responde a otras personas, súbela.'),
            ],
            if (v.lastRejectedVoice)
              Text('La última frase no parecía tu voz y se ignoró.',
                  style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}
