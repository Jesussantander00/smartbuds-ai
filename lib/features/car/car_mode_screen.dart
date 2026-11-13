import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';

/// Modo carro: pantalla grande, pocos botones y la voz como control principal.
///
/// Límite honesto: no es Android Auto ni CarPlay. Esas pantallas solo aceptan
/// apps que reproducen su propia música (Spotify, YouTube Music, Apple Music ya
/// están ahí). SmartBuds se usa en el teléfono, idealmente en un soporte, con la
/// voz y mirando solo con el carro detenido.
class CarModeScreen extends StatefulWidget {
  const CarModeScreen({super.key, required this.assistant, this.voice});
  final Assistant assistant;
  final VoiceEngine? voice;

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen> {
  Assistant get a => widget.assistant;
  VoiceEngine? get v => widget.voice ?? a.voice;

  @override
  void initState() {
    super.initState();
    // En el carro conviene escuchar siempre: se activa la voz si estaba apagada.
    final voice = v;
    if (voice != null && !voice.enabled) voice.start();
  }

  /// El panel principal cierra esta pantalla al apagar el modo carro.
  void _close() {
    if (a.carMode) {
      a.setCarMode(false);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _cmd(MusicCommand c) async {
    HapticFeedback.mediumImpact();
    await a.handleCommand(c);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listen = Listenable.merge([a, a.controller, if (v != null) v!]);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) a.setCarMode(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: listen,
            builder: (context, _) {
              final s = a.active;
              final playing = s?.isPlaying ?? false;
              final hearing = v?.listening ?? false;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.directions_car_rounded, color: Colors.white70, size: 30),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Modo carro',
                              style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w600)),
                        ),
                        TextButton.icon(
                          onPressed: _close,
                          icon: const Icon(Icons.close_rounded, size: 30),
                          label: const Text('Salir', style: TextStyle(fontSize: 20)),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      s?.title ?? 'Nada sonando',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [s?.artist, s?.appName].whereType<String>().join(' · '),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 22),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(child: _big(Icons.skip_previous_rounded, 'Anterior', () => _cmd(MusicCommand.previous))),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _big(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            playing ? 'Pausa' : 'Reproducir',
                            () => _cmd(MusicCommand.togglePlayPause),
                            color: Neon.cyan,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: _big(Icons.skip_next_rounded, 'Siguiente', () => _cmd(MusicCommand.next))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _big(Icons.favorite_rounded, 'Me gusta', () {
                            HapticFeedback.mediumImpact();
                            final t = a.profile.like();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(t == null ? 'No hay música sonando' : 'Guardada en tus favoritas'),
                            ));
                          }, height: 96),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _big(
                            hearing ? Icons.mic_rounded : Icons.mic_off_rounded,
                            hearing ? 'Te escucho' : 'Activar voz',
                            v == null
                                ? null
                                : () async {
                                    HapticFeedback.mediumImpact();
                                    if (v!.enabled) {
                                      await v!.stop();
                                    } else {
                                      await v!.start();
                                    }
                                  },
                            height: 96,
                            color: hearing ? const Color(0xFF1FA889) : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Di «Cambia», «Pausa» o «Pon algo de…». Mira la pantalla solo con el carro detenido.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _big(IconData icon, String label, VoidCallback? onTap, {double height = 130, Color? color}) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: color ?? const Color(0xFF26262B),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: height * .45),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
}
