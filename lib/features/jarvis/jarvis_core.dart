import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/voice_engine/voice_engine.dart';

/// Núcleo animado de Jarvis: cambia de color y de movimiento según esté
/// esperando, escuchando, ejecutando o respondiendo. Respeta «reducir movimiento».
class JarvisCore extends StatefulWidget {
  const JarvisCore({super.key, required this.voice, this.size = 120, this.showLabel = true});
  final VoiceEngine voice;
  final double size;
  final bool showLabel;

  static String label(JarvisState s) => switch (s) {
        JarvisState.off => 'Apagado',
        JarvisState.waiting => 'Esperando',
        JarvisState.listening => 'Escuchando',
        JarvisState.working => 'Ejecutando',
        JarvisState.responding => 'Respondiendo',
      };

  static Color color(JarvisState s) => switch (s) {
        JarvisState.off => const Color(0xFF8A8F98),
        JarvisState.waiting => const Color(0xFFE8833A),
        JarvisState.listening => const Color(0xFF2FB5FF),
        JarvisState.working => const Color(0xFFB07CFF),
        JarvisState.responding => const Color(0xFF1FD1A0),
      };

  @override
  State<JarvisCore> createState() => _JarvisCoreState();
}

class _JarvisCoreState extends State<JarvisCore> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    widget.voice.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  void _sync() {
    final want = !_reduce && widget.voice.enabled;
    if (want && !_c.isAnimating) _c.repeat();
    if (!want && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    widget.voice.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.voice, _c]),
        builder: (context, _) {
          final state = widget.voice.jarvisState;
          return Semantics(
            label: 'Jarvis: ${JarvisCore.label(state)}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: widget.size,
                  child: CustomPaint(painter: _CorePainter(state, _reduce ? 0 : _c.value)),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 6),
                  Text(
                    JarvisCore.label(state).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: JarvisCore.color(state),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

class _CorePainter extends CustomPainter {
  _CorePainter(this.state, this.t);
  final JarvisState state;
  final double t; // 0–1, gira con el tiempo

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final color = JarvisCore.color(state);
    final speed = switch (state) {
      JarvisState.off => 0.0,
      JarvisState.waiting => 1.0,
      JarvisState.listening => 2.5,
      JarvisState.working => 4.0,
      JarvisState.responding => 1.8,
    };
    final a = t * 2 * pi * speed;

    // Halo.
    canvas.drawCircle(
      c,
      r * .95,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: .35), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Marcas del dial.
    final tick = Paint()
      ..color = color.withValues(alpha: .55)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 48; i++) {
      final ang = i / 48 * 2 * pi;
      final inner = i % 4 == 0 ? r * .78 : r * .82;
      canvas.drawLine(c + Offset(cos(ang), sin(ang)) * inner, c + Offset(cos(ang), sin(ang)) * r * .86, tick);
    }
    // Arcos que giran en sentidos opuestos.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * .05
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * .7), a, pi * .7, false, arc);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * .7), a + pi, pi * .35, false, arc..color = color.withValues(alpha: .5));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * .58), -a * 1.3, pi * .9, false,
        arc..color = color.withValues(alpha: .75));
    // Escuchando: ondas; respondiendo: pulso.
    final pulse = state == JarvisState.listening || state == JarvisState.responding ? (sin(a * 2) + 1) / 2 : 0.0;
    if (state == JarvisState.listening) {
      for (var k = 0; k < 3; k++) {
        final p = (t * speed + k / 3) % 1;
        canvas.drawCircle(
          c,
          r * (.35 + p * .5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: (1 - p) * .6),
        );
      }
    }
    // Núcleo.
    final coreR = r * (.32 + pulse * .04);
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.3),
          colors: [Colors.white, color, Color.lerp(color, Colors.black, .35)!],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: coreR)),
    );
  }

  @override
  bool shouldRepaint(_CorePainter old) => old.t != t || old.state != state;
}
