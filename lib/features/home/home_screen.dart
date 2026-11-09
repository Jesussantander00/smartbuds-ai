import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../../core/ui/futuristic.dart';
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

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      widget.controller,
      widget.assistant,
      if (widget.voice != null) widget.voice!,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartBuds AI'),
        actions: [
          IconButton(
            tooltip: 'Compartir canción',
            icon: const Icon(Icons.share),
            onPressed: widget.assistant.shareCurrent,
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
          padding: const EdgeInsets.all(16),
          children: [
            _NowPlaying(detection: widget.controller.detection, assistant: widget.assistant),
            _ExtrasRow(assistant: widget.assistant),
            if (widget.assistant.queue.isNotEmpty) _QueueCard(assistant: widget.assistant),
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
            const SizedBox(height: 16),
            if (widget.voice != null) _MicCard(voice: widget.voice!),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => widget.controller.search(_query.text),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Buscar una canción',
                      hintText: 'Ojalá Ryan Castro',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Buscar',
                  onPressed: widget.controller.busy
                      ? null
                      : () => widget.controller.search(_query.text),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: widget.controller.busy ? null : widget.assistant.playFavorite,
              icon: const Icon(Icons.favorite),
              label: const Text('Pon algo que me guste'),
            ),
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
  const _NowPlaying({required this.detection, required this.assistant});
  final DetectionResult detection;
  final Assistant assistant;

  @override
  State<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<_NowPlaying> {
  Timer? _tick;
  DateTime _receivedAt = DateTime.now();
  int? _lastPos;
  double? _dragging;

  PlayerStatus? get _status {
    final d = widget.detection;
    return d is PlayerDetected ? d.candidate.status : null;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status?.isPlaying == true && _dragging == null && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _NowPlaying old) {
    super.didUpdateWidget(old);
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
    final m = t.inMinutes;
    final sec = (t.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detection = widget.detection;
    final (String app, String? title, String? artist) = switch (detection) {
      PlayerDetected(:final candidate) => (
          candidate.status.appName,
          candidate.status.title,
          candidate.status.artist,
        ),
      NeedsChoice() => ('Varios reproductores', 'Revisa la pestaña Dispositivos', null),
      NoPlayer() => ('Sin música', 'Pon algo en tu app de música o di «Busca…»', null),
    };
    final s = _status;
    final playing = s?.isPlaying ?? false;
    final art = s?.art;
    final duration = s?.durationMs;
    final pos = s == null ? null : _positionNow(s);

    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: art != null
                    ? ClipRRect(
                        key: ValueKey(s?.trackKey),
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(art,
                            width: 72, height: 72, fit: BoxFit.cover, gaplessPlayback: true),
                      )
                    : SizedBox(
                        key: const ValueKey('eq'),
                        width: 72,
                        height: 72,
                        child: Center(child: NeonEqualizer(playing: playing)),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.4)),
                    const SizedBox(height: 4),
                    if (title != null)
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    if (artist != null && artist.isNotEmpty)
                      Text(artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              if (art != null && playing) NeonEqualizer(playing: playing, height: 24),
            ],
          ),
          if (s != null && duration != null && duration > 0 && pos != null) ...[
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: (_dragging ?? pos / duration).clamp(0.0, 1.0).toDouble(),
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) async {
                  final target = (v * duration).round();
                  setState(() => _dragging = null);
                  final ok = await widget.assistant.media
                          ?.seek(s.playerId, positionMs: target) ??
                      false;
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Este reproductor no deja adelantar.')));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
          if (s != null && (title ?? '').isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Me gusta',
                  icon: const Icon(Icons.favorite_border),
                  onPressed: () => widget.assistant.handleIntent(const LikeIntent()),
                ),
                IconButton(
                  tooltip: 'Nunca más esta',
                  icon: const Icon(Icons.block),
                  onPressed: () => widget.assistant.blockCurrent(),
                ),
                IconButton(
                  tooltip: 'Compartir',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: widget.assistant.shareCurrent,
                ),
              ],
            ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            dense: true,
            leading: Icon(Icons.queue_music),
            title: Text('Sigue después'),
          ),
          for (var i = 0; i < assistant.queue.length; i++)
            ListTile(
              dense: true,
              title: Text(assistant.queue[i]),
              leading: Text('${i + 1}'),
              trailing: IconButton(
                tooltip: 'Quitar',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => assistant.removeFromQueue(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _MicCard extends StatelessWidget {
  const _MicCard({required this.voice});
  final VoiceEngine voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = voice.enabled;
    final status = !on
        ? 'Toca para que SmartBuds te escuche'
        : voice.askingForSong
            ? '¿Qué canción? Dila ahora…'
            : voice.paused
                ? 'En pausa: conecta tus audífonos para seguir'
                : voice.listening
                    ? 'Escuchando, también con la pantalla apagada'
                    : 'Preparando el micrófono…';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Tooltip(
              message: on ? 'Dejar de escuchar' : 'Escuchar',
              child: MicOrb(
                on: on,
                listening: voice.listening && !voice.paused,
                onTap: voice.toggle,
                icon: on ? (voice.paused ? Icons.mic_off : Icons.mic) : Icons.mic_none,
              ),
            ),
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
            if (voice.lastHeard.isNotEmpty)
              Text('Oí: «${voice.lastHeard}»', style: theme.textTheme.bodySmall),
            if (voice.error != null)
              Text(voice.error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(voice.headphonesConnected ? Icons.headphones : Icons.headset_off,
                  size: 18),
              label: Text(voice.headphonesConnected
                  ? 'Audífonos conectados'
                  : 'Sin audífonos'),
            ),
          ],
        ),
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
