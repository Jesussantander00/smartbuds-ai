import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'futuristic.dart';

/// Color de la carátula que suena (para teñir el fondo de toda la app).
class ArtAmbient {
  static final ValueNotifier<Color?> color = ValueNotifier<Color?>(null);
}

/// Bandas de frecuencia del audio real (solo Android; algunos fabricantes lo
/// bloquean). Emite listas de 16 valores 0–1, o null si no está disponible.
class AudioBands {
  AudioBands._();
  static final AudioBands instance = AudioBands._();

  static const _channel = EventChannel('smartbuds/visualizer');
  final ValueNotifier<List<double>?> bands = ValueNotifier<List<double>?>(null);

  /// false cuando el teléfono no permite leer el audio (se usa la animación normal).
  bool available = !kIsWeb && Platform.isAndroid;
  StreamSubscription<dynamic>? _sub;
  int _listeners = 0;

  /// Cuadros seguidos en silencio y si alguna vez llegó sonido real.
  int _silent = 0;
  bool _heard = false;

  /// Con ~15 cuadros por segundo: 3 s de silencio → animación normal;
  /// 10 s sin haber oído nada nunca → el fabricante lo bloquea: se apaga
  /// la captura para no gastar batería.
  static const silentToFallback = 45;
  static const neverHeardLimit = 150;

  /// Procesa un cuadro de bandas (público para las pruebas).
  @visibleForTesting
  void onBands(List<double> b) {
    final loud = b.any((v) => v > .01);
    if (loud) {
      _heard = true;
      _silent = 0;
      bands.value = b;
      return;
    }
    _silent++;
    if (!_heard && _silent >= neverHeardLimit) {
      available = false;
      bands.value = null;
      _sub?.cancel();
      _sub = null;
      return;
    }
    if (_silent >= silentToFallback) {
      bands.value = null;
    } else if (bands.value != null) {
      bands.value = b;
    }
  }

  void acquire() {
    _listeners++;
    if (_sub != null || !available) return;
    _sub = _channel.receiveBroadcastStream().listen((e) {
      if (e is Map && e['unavailable'] != null) {
        available = false;
        bands.value = null;
        _sub?.cancel();
        _sub = null;
        return;
      }
      if (e is Map && e['bands'] is List) {
        onBands((e['bands'] as List).map((v) => (v as num).toDouble()).toList());
      }
    }, onError: (_) {
      available = false;
      bands.value = null;
    });
  }

  void release() {
    _listeners = math.max(0, _listeners - 1);
    if (_listeners == 0) {
      _sub?.cancel();
      _sub = null;
      bands.value = null;
      _silent = 0;
    }
  }
}

/// Visualizador inteligente: barras que siguen el audio real cuando el
/// teléfono lo permite; si no, el ecualizador animado de siempre.
class LiveVisualizer extends StatefulWidget {
  const LiveVisualizer({super.key, required this.playing, this.height = 48, this.enabled = true, this.color});

  final bool playing;
  final double height;

  /// Ajuste «Visualizador con el audio real».
  final bool enabled;
  final Color? color;

  @override
  State<LiveVisualizer> createState() => _LiveVisualizerState();
}

class _LiveVisualizerState extends State<LiveVisualizer> {
  bool _acquired = false;
  bool _reduce = false;

  void _sync() {
    final want = widget.enabled && widget.playing && !_reduce;
    if (want && !_acquired) {
      AudioBands.instance.acquire();
      _acquired = true;
    } else if (!want && _acquired) {
      AudioBands.instance.release();
      _acquired = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // «Reducir movimiento» del teléfono: sin captura de audio ni barras vivas.
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(LiveVisualizer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    if (_acquired) AudioBands.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Neon.cyan;
    return ValueListenableBuilder<List<double>?>(
      valueListenable: AudioBands.instance.bands,
      builder: (context, bands, _) {
        if (bands == null || !widget.enabled || !widget.playing || _reduce) {
          return NeonEqualizer(playing: widget.playing, height: widget.height * .6, color: color);
        }
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in bands)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  width: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: 4 + (widget.height - 4) * v,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [color, color.withValues(alpha: .55)],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Carátula viva: «respira» suavemente y brilla con su color mientras suena.
/// Se apaga en Ajustes o si el teléfono pide menos movimiento.
class LiveArt extends StatefulWidget {
  const LiveArt({
    super.key,
    required this.child,
    required this.playing,
    this.enabled = true,
    this.glow,
    this.intensity = 1,
    this.tempo = 1,
  });

  /// Fuerza del efecto (0 = nada, 1 = normal, 2 = intenso).
  final double intensity;

  /// Velocidad según la canción (ambiente enérgico = más rápido).
  final double tempo;

  final Widget child;
  final bool playing;
  final bool enabled;
  final Color? glow;

  @override
  State<LiveArt> createState() => _LiveArtState();
}

class _LiveArtState extends State<LiveArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LiveArt old) {
    super.didUpdateWidget(old);
    // Ritmo por canción: ambiente enérgico = más rápido.
    if (old.tempo != widget.tempo) {
      _c.duration = Duration(milliseconds: (6000 / widget.tempo.clamp(.5, 3)).round());
      if (_c.isAnimating) _c.repeat(reverse: true);
    }
    _sync();
  }

  void _sync() {
    // Sin animación (ni consumo) si está apagada, en pausa o con «reducir movimiento».
    if (widget.enabled && widget.playing && !_reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduce || widget.intensity <= 0) return widget.child;
    final k = widget.intensity;
    final glow = widget.glow ?? Neon.cyan;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 1 + .03 * k * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: widget.playing
                  ? [
                      BoxShadow(
                        color: glow.withValues(alpha: ((.25 + .25 * t) * k).clamp(0, 1).toDouble()),
                        blurRadius: (30 + 20 * t) * k,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Velocidad del efecto según el ambiente de la canción (no se analiza el
/// audio: las apps no comparten el ritmo). Enérgica = más rápido, tranquila = lento.
double songTempo(String? mood) {
  final m = (mood ?? '').toLowerCase();
  if (RegExp(r'entrenar|fiesta|bailar|energ|perrear|correr').hasMatch(m)) return 2;
  if (RegExp(r'dormir|tranquil|relaj|calma|triste').hasMatch(m)) return .6;
  return 1;
}
