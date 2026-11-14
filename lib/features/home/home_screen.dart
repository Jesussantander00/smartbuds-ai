import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/command_parser.dart';
import '../music_profile/insights.dart';
import '../brain/music_brain.dart';
import '../../core/ui/live_visuals.dart';
import 'immersive_screen.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../../core/ui/futuristic.dart';
import '../../core/ui/art_color.dart';
import '../../core/settings/app_settings.dart';
import '../assistant/assistant.dart';
import 'car_mode_screen.dart';
import '../devices/detected_player_controller.dart';

/// Inicio: qué suena, el micrófono y la búsqueda rápida.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.assistant,
    this.voice,
  });

  final DetectedPlayerController controller;
  final Assistant assistant;
  final VoiceEngine? voice;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Una sección de Inicio (el orden y cuáles se ven se eligen en «Personalizar»).
  List<Widget> _section(String id) => switch (id) {
        'now' => [
            _NowPlaying(
                detection: widget.controller.detection,
                assistant: widget.assistant,
                controller: widget.controller),
          ],
        'foryou' => [_ForYou(assistant: widget.assistant)],
        'extras' => [_ExtrasRow(assistant: widget.assistant)],
        'queue' => [
            if (widget.assistant.queue.isNotEmpty) _QueueCard(assistant: widget.assistant),
          ],
        'suggestion' => [
            if (widget.assistant.contextSuggestion != null)
              Card(
                child: ListTile(
                  leading: Icon(widget.assistant.weatherMood != null
                      ? Icons.wb_cloudy_outlined
                      : Icons.schedule),
                  title: Text(widget.assistant.contextSuggestion!),
                  trailing: TextButton(
                    onPressed: () {
                      final w = widget.assistant.weatherMood;
                      if (w != null) {
                        widget.assistant.playMood(w.mood, w.query);
                      } else {
                        widget.assistant.playFavorite();
                      }
                    },
                    child: const Text('Sí'),
                  ),
                ),
              ),
          ],
        'search' => [
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => widget.controller.search(_query.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Buscar una canción',
                      hintText: 'Ojalá Ryan Castro',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Buscar',
                  onPressed: widget.controller.busy ? null : () => widget.controller.search(_query.text),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ],
        'favorite' => [
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: widget.controller.busy ? null : widget.assistant.playFavorite,
              icon: const Icon(Icons.favorite),
              label: const Text('Pon algo que me guste'),
            ),
          ],
        _ => const [],
      };

  /// «Personalizar Inicio»: orden y secciones visibles, modo compacto,
  /// colores de la carátula y perfil de uso.
  Future<void> _customize() async {
    final settings = widget.assistant.settings;
    if (settings == null) return;
    const names = {
      'now': ('Sonando ahora', Icons.album_rounded),
      'foryou': ('Para ti ahora', Icons.auto_awesome_rounded),
      'extras': ('Accesos rápidos', Icons.bolt_rounded),
      'queue': ('Cola', Icons.queue_music_rounded),
      'suggestion': ('Sugerencias', Icons.lightbulb_outline_rounded),
      'search': ('Buscar', Icons.search_rounded),
      'favorite': ('Pon algo que me guste', Icons.favorite_rounded),
    };
    final order = [
      ...settings.homeSections,
      ...AppSettings.allHomeSections.where((s) => !settings.homeSections.contains(s)),
    ];
    final visible = {...settings.homeSections};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void save() => settings.setHomeSections([for (final s in order) if (visible.contains(s)) s]);
          final theme = Theme.of(context);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .8,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  Text('Personalizar Inicio', style: theme.textTheme.titleLarge),
                  Text('Arrastra para ordenar; apaga lo que no quieras ver.', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: (a, b) {
                      setSheet(() {
                        if (b > a) b--;
                        order.insert(b, order.removeAt(a));
                      });
                      save();
                    },
                    children: [
                      for (var i = 0; i < order.length; i++)
                        ListTile(
                          key: ValueKey(order[i]),
                          contentPadding: EdgeInsets.zero,
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_indicator_rounded),
                          ),
                          title: Row(
                            children: [
                              Icon(names[order[i]]!.$2, size: 20),
                              const SizedBox(width: 8),
                              Text(names[order[i]]!.$1),
                            ],
                          ),
                          trailing: Switch(
                            value: visible.contains(order[i]),
                            onChanged: (v) {
                              setSheet(() => v ? visible.add(order[i]) : visible.remove(order[i]));
                              save();
                            },
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Modo compacto'),
                    subtitle: const Text('Carátula pequeña y menos botones (pantallas pequeñas).'),
                    value: settings.compact,
                    onChanged: (v) {
                      settings.update(compact: v);
                      setSheet(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Carátulas vivas'),
                    subtitle: const Text('La portada respira y brilla suavemente mientras suena.'),
                    value: settings.liveArt,
                    onChanged: (v) {
                      settings.update(liveArt: v);
                      setSheet(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Visualizador con el audio real'),
                    subtitle: const Text('En Android, si el teléfono lo permite; si no, animación normal.'),
                    value: settings.realVisualizer,
                    onChanged: (v) {
                      settings.update(realVisualizer: v);
                      setSheet(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Colores de la carátula'),
                    subtitle: const Text('La tarjeta y el fondo toman el color de la portada.'),
                    value: settings.dynamicColors,
                    onChanged: (v) {
                      settings.update(dynamicColors: v);
                      if (!v) ArtAmbient.color.value = null;
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Perfil de uso', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'diario', label: Text('Diario'), icon: Icon(Icons.wb_sunny_outlined)),
                      ButtonSegment(value: 'estudio', label: Text('Estudio'), icon: Icon(Icons.menu_book_rounded)),
                      ButtonSegment(value: 'viaje', label: Text('Viaje'), icon: Icon(Icons.directions_car_rounded)),
                    ],
                    emptySelectionAllowed: true,
                    selected: {if (settings.usageProfile != null) settings.usageProfile!},
                    onSelectionChanged: (v) {
                      if (v.isEmpty) return;
                      settings.applyUsageProfile(v.first);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Estudio: respuestas cortas, sin anuncios, radio con conocidas. '
                    'Viaje: radio con anuncios y descubrimientos. Diario: lo normal.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      widget.controller,
      widget.assistant,
      if (widget.assistant.settings != null) widget.assistant.settings!,
      if (widget.voice != null) widget.voice!,
    ];
    final voice = widget.voice;
    return Scaffold(
      floatingActionButton: voice == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListenableBuilder(
                listenable: voice,
                builder: (context, _) => Semantics(
                  button: true,
                  label: voice.enabled ? 'Dejar de escuchar' : 'Escuchar',
                  child: MicOrb(
                    size: 92,
                    on: voice.enabled,
                    listening: voice.listening && !voice.paused,
                    onTap: voice.toggle,
                    icon: voice.enabled
                        ? (voice.paused ? Icons.mic_off : Icons.mic)
                        : Icons.mic_none,
                  ),
                ),
              ),
            ),
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (r) => Neon.gradient.createShader(r),
              child: const Icon(Icons.headphones, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 10),
            const Text('SmartBuds'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Personalizar Inicio',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: _customize,
          ),
          ListenableBuilder(
            listenable: Listenable.merge(listenables),
            builder: (context, _) => _ConnectionPill(
              controller: widget.controller,
              assistant: widget.assistant,
              voice: voice,
            ),
          ),
          IconButton(
            tooltip: 'Modo carro',
            icon: const Icon(Icons.directions_car),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CarModeScreen(
                controller: widget.controller,
                assistant: widget.assistant,
                voice: widget.voice,
              ),
            )),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 120),
          children: [
            if (voice != null) _MicStatus(voice: voice),
            for (final id in widget.assistant.settings?.homeSections ?? AppSettings.allHomeSections)
              ..._section(id),
            if (widget.controller.lastResult != null) ...[
              const SizedBox(height: 12),
              _ResultLine(result: widget.controller.lastResult!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Qué suena: carátula, título, barra de progreso y acciones rápidas.
class _NowPlaying extends StatefulWidget {
  const _NowPlaying({required this.detection, required this.assistant, required this.controller});
  final DetectionResult detection;
  final Assistant assistant;
  final DetectedPlayerController controller;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  Timer? _tick;
  DateTime _receivedAt = DateTime.now();
  int? _lastPos;
  double? _dragging;
  Color? _artColor;
  String? _artKey;

  void _updateArtColor() {
    final s = _status;
    final art = s?.art;
    final key = s?.trackKey;
    if (key == _artKey) return;
    _artKey = key;
    if (art == null || !(widget.assistant.settings?.dynamicColors ?? true)) {
      if (_artColor != null) setState(() => _artColor = null);
      ArtAmbient.color.value = null;
      return;
    }
    ArtColor.of(art).then((c) {
      if (mounted && _artKey == key) setState(() => _artColor = c);
      ArtAmbient.color.value = c; // ambiente visual automático
    });
  }

  PlayerStatus? get _status {
    final d = widget.detection;
    return d is PlayerDetected ? d.candidate.status : null;
  }

  @override
  void initState() {
    super.initState();
    _updateArtColor();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status?.isPlaying == true && _dragging == null && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _NowPlaying old) {
    super.didUpdateWidget(old);
    _updateArtColor();
    final pos = _status?.positionMs;
    if (pos != _lastPos) {
      _lastPos = pos;
      _receivedAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Posición estimada ahora (la app solo avisa cuando algo cambia).
  int? _positionNow(PlayerStatus s) {
    final p = s.positionMs;
    if (p == null) return null;
    final extra = s.isPlaying ? DateTime.now().difference(_receivedAt).inMilliseconds : 0;
    final d = s.durationMs;
    final now = p + extra;
    return d != null && now > d ? d : now;
  }

  static String _fmt(int ms) {
    final t = Duration(milliseconds: ms);
    return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String app, String? title, String? artist) = switch (widget.detection) {
      PlayerDetected(:final candidate) => (
          candidate.status.appName,
          candidate.status.title,
          candidate.status.artist,
        ),
      NeedsChoice() => ('Varios reproductores', 'Elige uno en Dispositivos', null),
      NoPlayer() => ('Nada sonando', 'Pon música o toca el micrófono y di «Busca…»', null),
    };
    final s = _status;
    final playing = s?.isPlaying ?? false;
    final art = s?.art;
    final duration = s?.durationMs;
    final pos = s == null ? null : _positionNow(s);
    final busy = widget.controller.busy;
    final compact = widget.assistant.settings?.compact ?? false;
    final dynamicOn = widget.assistant.settings?.dynamicColors ?? true;

    Widget control(IconData icon, String label, MusicCommand cmd, {bool main = false}) {
      final button = main
          ? DecoratedBox(
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Neon.gradient),
              child: IconButton(
                tooltip: label,
                iconSize: 40,
                padding: const EdgeInsets.all(14),
                color: Colors.white,
                onPressed: s == null || busy ? null : () => widget.controller.send(cmd),
                icon: Icon(icon),
              ),
            )
          : IconButton(
              tooltip: label,
              iconSize: 36,
              padding: const EdgeInsets.all(12),
              onPressed: s == null || busy ? null : () => widget.controller.send(cmd),
              icon: Icon(icon),
            );
      return button;
    }

    return NeonCard(
      tint: dynamicOn ? _artColor : null,
      padding: EdgeInsets.fromLTRB(20, compact ? 14 : 20, 20, compact ? 6 : 12),
      child: Column(
        children: [
          // Carátula: la protagonista.
          LayoutBuilder(
            builder: (context, c) {
              final side = c.maxWidth.clamp(0.0, compact ? 140.0 : 300.0).toDouble();
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => ImmersiveScreen(assistant: widget.assistant, controller: widget.controller),
                )),
                child: LiveArt(
                playing: playing,
                enabled: (widget.assistant.settings?.liveArt ?? true) && !widget.assistant.lowBattery,
                glow: _artColor,
                child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: Container(
                  key: ValueKey(s?.trackKey ?? 'none'),
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .12),
                          blurRadius: 36,
                          offset: const Offset(0, 16)),
                    ],
                    gradient: art == null
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Neon.cyan.withValues(alpha: .85),
                              Neon.violet,
                            ],
                          )
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: art != null
                      ? Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true,
                          semanticLabel: 'Carátula de ${title ?? 'la canción'}')
                      : Center(
                          child: playing
                              ? const NeonEqualizer(playing: true, height: 64)
                              : Icon(Icons.music_note_rounded,
                                  size: 96, color: Colors.white.withValues(alpha: .9)),
                        ),
                ),
              ),
              ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(title ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (artist != null && artist.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(artist,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: .7))),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playing) ...[
                LiveVisualizer(
                  playing: true,
                  height: 16,
                  enabled: (widget.assistant.settings?.realVisualizer ?? true) &&
                      (widget.assistant.settings?.moduleOn('visualizer') ?? true) &&
                      !widget.assistant.lowBattery,
                  color: _artColor,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                [
                  app.toUpperCase(),
                  if ((s?.album ?? '').isNotEmpty) s!.album!,
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: Neon.cyan),
              ),
            ],
          ),
          if (s != null && duration != null && duration > 0 && pos != null) ...[
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                semanticFormatterCallback: (v) => _fmt((v * duration).round()),
                value: (_dragging ?? pos / duration).clamp(0.0, 1.0).toDouble(),
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) async {
                  final target = (v * duration).round();
                  setState(() => _dragging = null);
                  final ok = await widget.assistant.media?.seek(s.playerId, positionMs: target) ??
                      false;
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Este reproductor no deja adelantar.')));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(_fmt(_dragging == null ? pos : (_dragging! * duration).round()),
                      style: theme.textTheme.labelSmall),
                  const Spacer(),
                  Text(_fmt(duration), style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              control(Icons.skip_previous_rounded, 'Anterior', MusicCommand.previous),
              control(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  playing ? 'Pausa' : 'Reproducir', MusicCommand.togglePlayPause,
                  main: true),
              control(Icons.skip_next_rounded, 'Siguiente', MusicCommand.next),
            ],
          ),
          if (s != null && (title ?? '').isNotEmpty && !compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Me gusta',
                  icon: const Icon(Icons.favorite_border_rounded),
                  onPressed: () => widget.assistant.handleIntent(const LikeIntent()),
                ),
                IconButton(
                  tooltip: 'Nunca más esta',
                  icon: const Icon(Icons.block_rounded),
                  onPressed: () => widget.assistant.blockCurrent(),
                ),
                IconButton(
                  tooltip: 'Modo inmersivo',
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => ImmersiveScreen(assistant: widget.assistant, controller: widget.controller),
                  )),
                ),
                IconButton(
                  tooltip: 'Parecidas a esta',
                  icon: const Icon(Icons.auto_awesome_motion_rounded),
                  onPressed: () => showSimilarSheet(context, widget.assistant),
                ),
                IconButton(
                  tooltip: '¿Por qué esta?',
                  icon: const Icon(Icons.insights_rounded),
                  onPressed: () => showWhySheet(context, widget.assistant),
                ),
                IconButton(
                  tooltip: 'Compartir',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: widget.assistant.shareCurrent,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Estado del micrófono en una línea (el botón flota abajo a la derecha).
class _MicStatus extends StatelessWidget {
  const _MicStatus({required this.voice});
  final VoiceEngine voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String text) = !voice.enabled
        ? (Icons.mic_off_rounded, theme.colorScheme.onSurfaceVariant, 'Micrófono apagado · toca el botón para hablar')
        : voice.error != null
            ? (Icons.error_outline, theme.colorScheme.error, voice.error!)
            : voice.askingForSong
                ? (Icons.hearing, const Color(0xFFB9762A), 'Dime la canción…')
                : voice.paused
                    ? (Icons.headset_off, Colors.orangeAccent, 'En pausa: conecta tus audífonos')
                    : voice.listening
                        ? (Icons.graphic_eq, const Color(0xFFB9762A), 'Escuchando')
                        : (Icons.hourglass_top, theme.colorScheme.onSurfaceVariant, 'Preparando el micrófono…');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              voice.lastHeard.isNotEmpty && voice.enabled ? '$text · «${voice.lastHeard}»' : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado: ¿hay reproductor y audífonos?
class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.controller, required this.assistant, this.voice});
  final DetectedPlayerController controller;
  final Assistant assistant;
  final VoiceEngine? voice;

  @override
  Widget build(BuildContext context) {
    final player = controller.detection is PlayerDetected;
    final phones = assistant.headphoneName != null || (voice?.headphonesConnected ?? false);
    final ok = player || phones;
    return Tooltip(
      message: [
        player ? 'Reproductor conectado' : 'Sin reproductor',
        phones ? (assistant.headphoneName ?? 'Audífonos conectados') : 'Sin audífonos',
      ].join(' · '),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? Neon.cyan : Theme.of(context).colorScheme.outline,
                boxShadow: null,
              ),
            ),
            const SizedBox(width: 6),
            Icon(phones ? Icons.headphones : Icons.headset_off, size: 16),
          ],
        ),
      ),
    );
  }
}

/// «Para ti ahora»: lo que el cerebro musical cree que quieres escuchar,
/// con el porqué. Solo suena si lo tocas.
class _ForYou extends StatelessWidget {
  const _ForYou({required this.assistant});
  final Assistant assistant;

  static const _icons = {
    RecKind.favorite: Icons.favorite_rounded,
    RecKind.rediscover: Icons.history_rounded,
    RecKind.rising: Icons.trending_up_rounded,
    RecKind.mood: Icons.mood_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final recs = assistant.forYou(n: 6);
    final ready = assistant.brain.readiness();
    if (recs.isEmpty && !ready.learning) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 18, color: Neon.cyan),
              const SizedBox(width: 6),
              Text('Para ti ahora', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        // Con pocos datos lo dice: no finge conocerte todavía.
        if (ready.learning)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              radius: 16,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Todavía estoy aprendiendo tus gustos: llevo ${ready.plays} de ${ready.needed} canciones. '
                      'Las sugerencias mejoran a medida que escuchas.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (recs.isNotEmpty)
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final r = recs[i];
              return SizedBox(
                width: 210,
                child: Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => assistant.playRecommendation(r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_icons[r.kind], size: 16, color: Neon.cyan),
                            const Spacer(),
                            const Icon(Icons.play_circle_fill_rounded, color: Neon.cyan),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(r.track.artist ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                        const Spacer(),
                        Text(r.reasons.first,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// «Después pon …»: lo que va a sonar.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.assistant});
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: assistant.queue.length <= 3,
        shape: const Border(),
        leading: const Icon(Icons.queue_music_rounded),
        title: Text('Sigue después (${assistant.queue.length})'),
        children: [
          for (var i = 0; i < assistant.queue.length; i++)
            ListTile(
              dense: true,
              title: Text(assistant.queue[i]),
              leading: Text('${i + 1}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    IconButton(
                      tooltip: 'Subir',
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      onPressed: () => assistant.moveInQueue(i, i - 1),
                    ),
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      final removed = assistant.queue[i];
                      assistant.removeFromQueue(i);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text('Quitaste «$removed»'),
                          action: SnackBarAction(
                            label: 'Deshacer',
                            onPressed: () => assistant.restoreToQueue(i, removed),
                          ),
                        ));
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.result});
  final CommandResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.executed;
    return ListTile(
      leading: Icon(ok ? Icons.check_circle : Icons.info_outline,
          color: ok ? Colors.green : Colors.orange),
      title: Text(result.message),
    );
  }
}


/// Deshacer el último «Cambia», temporizador activo y radio.
class _ExtrasRow extends StatelessWidget {
  const _ExtrasRow({required this.assistant});

  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final sleepAt = assistant.sleepAt;
    final radio = assistant.settings?.radioMode ?? false;
    final chips = <Widget>[
      if (assistant.canUndo)
        ActionChip(
          avatar: const Icon(Icons.undo, size: 18),
          label: const Text('Deshacer «Cambia»'),
          onPressed: assistant.undo,
        ),
      if (sleepAt != null)
        InputChip(
          avatar: const Icon(Icons.bedtime, size: 18),
          label: Text('Se apaga a las ${TimeOfDay.fromDateTime(sleepAt).format(context)}'),
          onDeleted: assistant.cancelSleep,
        ),
      FilterChip(
        avatar: const Icon(Icons.radio, size: 18),
        label: const Text('Radio SmartBuds'),
        selected: radio,
        onSelected: assistant.setRadio,
      ),
      ActionChip(
        avatar: const Icon(Icons.timer_outlined, size: 18),
        label: const Text('Apagar en…'),
        onPressed: () => _pickSleep(context),
      ),
      ActionChip(
        avatar: const Icon(Icons.directions_car_rounded, size: 18),
        label: const Text('Modo viaje'),
        onPressed: () => assistant.useProfile('viaje'),
      ),
      ActionChip(
        avatar: const Icon(Icons.trending_up_rounded, size: 18),
        label: const Text('Subir la energía'),
        onPressed: assistant.energyRamp,
      ),
      if (assistant.headphoneName != null)
        Chip(
          avatar: const Icon(Icons.headphones, size: 18),
          label: Text(assistant.headphoneName!),
        ),
      if (assistant.lowBattery)
        Chip(
          avatar: const Icon(Icons.battery_alert, size: 18),
          label: Text('Ahorro de batería (${assistant.batteryLevel ?? 0} %)'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  Future<void> _pickSleep(BuildContext context) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final m in [10, 15, 20, 30, 45, 60])
              ListTile(
                leading: const Icon(Icons.bedtime),
                title: Text(m == 60 ? '1 hora' : '$m minutos'),
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (minutes != null) await assistant.sleepIn(minutes);
  }
}
