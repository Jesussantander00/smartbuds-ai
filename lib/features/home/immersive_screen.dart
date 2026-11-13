import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/ui/futuristic.dart';
import '../../core/ui/live_visuals.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import '../devices/detected_player_controller.dart';

/// Modo inmersivo: la pantalla entera para la canción. Portada grande (viva),
/// fondo con su color, visualizador, progreso y solo los controles esenciales.
/// Desliza hacia abajo o toca ✕ para salir.
class ImmersiveScreen extends StatefulWidget {
  const ImmersiveScreen({super.key, required this.assistant, required this.controller});

  final Assistant assistant;
  final DetectedPlayerController controller;

  @override
  State<ImmersiveScreen> createState() => _ImmersiveScreenState();
}

class _ImmersiveScreenState extends State<ImmersiveScreen> {
  Timer? _tick;
  DateTime _receivedAt = DateTime.now();
  int? _lastPos;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  PlayerStatus? get _status {
    final d = widget.controller.detection;
    return d is PlayerDetected ? d.candidate.status : null;
  }

  static String _fmt(int ms) {
    final t = Duration(milliseconds: ms < 0 ? 0 : ms);
    return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.assistant.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.assistant]),
      builder: (context, _) {
        final s = _status;
        if (s?.positionMs != _lastPos) {
          _lastPos = s?.positionMs;
          _receivedAt = DateTime.now();
        }
        final playing = s?.isPlaying ?? false;
        final d = s?.durationMs;
        final p0 = s?.positionMs;
        final pos = p0 == null
            ? null
            : (p0 + (playing ? DateTime.now().difference(_receivedAt).inMilliseconds : 0)).clamp(0, d ?? 1 << 31);
        return ValueListenableBuilder<Color?>(
          valueListenable: ArtAmbient.color,
          builder: (context, tint, _) {
            final accent = tint ?? Neon.cyan;
            return Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                onVerticalDragEnd: (e) {
                  if ((e.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fondo: la carátula muy desenfocada, o su color.
                    if (s?.art != null)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Image.memory(s!.art!, fit: BoxFit.cover, gaplessPlayback: true),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [accent.withValues(alpha: .7), Colors.black],
                          ),
                        ),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x55000000), Color(0xDD000000)],
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Salir',
                                  color: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                                const Spacer(),
                                Text((s?.appName ?? '').toUpperCase(),
                                    style: const TextStyle(color: Colors.white70, letterSpacing: 1.6, fontSize: 12)),
                                const Spacer(),
                                const SizedBox(width: 48),
                              ],
                            ),
                            const Spacer(),
                            LayoutBuilder(
                              builder: (context, c) {
                                final side = c.maxWidth.clamp(0.0, 360.0).toDouble();
                                return LiveArt(
                                  playing: playing,
                                  enabled: (settings?.liveArt ?? true) && !widget.assistant.lowBattery,
                                  glow: accent,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: s?.art != null
                                        ? Image.memory(s!.art!,
                                            width: side, height: side, fit: BoxFit.cover, gaplessPlayback: true)
                                        : Container(
                                            width: side,
                                            height: side,
                                            color: accent.withValues(alpha: .4),
                                            child: const Icon(Icons.music_note_rounded, size: 120, color: Colors.white70),
                                          ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            Text(s?.title ?? 'Nada sonando',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(s?.artist ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 17)),
                            const SizedBox(height: 18),
                            LiveVisualizer(
                              playing: playing,
                              height: 44,
                              enabled: (settings?.realVisualizer ?? true) && !widget.assistant.lowBattery,
                              color: accent,
                            ),
                            const SizedBox(height: 12),
                            if (d != null && d > 0 && pos != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (pos / d).clamp(0.0, 1.0).toDouble(),
                                  minHeight: 5,
                                  color: accent,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(_fmt(pos.toInt()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const Spacer(),
                                  Text('-${_fmt(d - pos.toInt())}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  tooltip: 'Me gusta',
                                  color: Colors.white,
                                  iconSize: 28,
                                  onPressed: () => widget.assistant.handleIntent(const LikeIntent()),
                                  icon: const Icon(Icons.favorite_border_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Anterior',
                                  color: Colors.white,
                                  iconSize: 44,
                                  onPressed: () => widget.controller.send(MusicCommand.previous),
                                  icon: const Icon(Icons.skip_previous_rounded),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                                  child: IconButton(
                                    tooltip: playing ? 'Pausa' : 'Reproducir',
                                    color: Colors.white,
                                    iconSize: 48,
                                    padding: const EdgeInsets.all(14),
                                    onPressed: () => widget.controller.send(MusicCommand.togglePlayPause),
                                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Siguiente',
                                  color: Colors.white,
                                  iconSize: 44,
                                  onPressed: () => widget.controller.send(MusicCommand.next),
                                  icon: const Icon(Icons.skip_next_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Nunca más esta',
                                  color: Colors.white,
                                  iconSize: 28,
                                  onPressed: widget.assistant.blockCurrent,
                                  icon: const Icon(Icons.block_rounded),
                                ),
                              ],
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
