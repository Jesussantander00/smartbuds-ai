import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Estilo futurista de SmartBuds: espacio oscuro, vidrio y neón.
/// Los mismos colores que la página web (cian → violeta → rosa).
class Neon {
  static const cyan = Color(0xFF00F0FF);
  static const violet = Color(0xFF8B5CFF);
  static const pink = Color(0xFFFF2BD6);
  static const space0 = Color(0xFF04050D);
  static const space1 = Color(0xFF0A0F2A);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, violet, pink],
    stops: [0, .55, 1],
  );

  static List<BoxShadow> glow([Color color = cyan, double strength = 1]) => [
        BoxShadow(color: color.withValues(alpha: .35 * strength), blurRadius: 24),
        BoxShadow(color: violet.withValues(alpha: .18 * strength), blurRadius: 60),
      ];
}

/// Tema: en modo oscuro, fondo transparente (se ve el espacio animado),
/// tarjetas de vidrio con borde de neón y barra inferior translúcida.
ThemeData smartBudsTheme(Brightness brightness, Color seed) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  if (!dark) return base;
  final line = Neon.cyan.withValues(alpha: .18);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Neon.space1,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: .055),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xCC0A0E24),
      surfaceTintColor: Colors.transparent,
      indicatorColor: Neon.cyan.withValues(alpha: .18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .85)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white.withValues(alpha: .06),
      side: BorderSide(color: line),
    ),
    dividerColor: line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black.withValues(alpha: .35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Neon.cyan),
      ),
    ),
  );
}

/// Fondo espacial con auroras de neón que se mueven despacio.
/// En modo claro es un degradado suave, sin animación.
class SpaceBackground extends StatefulWidget {
  const SpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  State<SpaceBackground> createState() => _SpaceBackgroundState();
}

class _SpaceBackgroundState extends State<SpaceBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.surfaceContainer],
          ),
        ),
        child: widget.child,
      );
    }
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) _c.stop();
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.1),
              radius: 1.4,
              colors: [Neon.space1, Neon.space0],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                _Blob(color: Neon.cyan, alignment: Alignment(-1.2 + t * .5, -1.1 + t * .3), size: 420, opacity: .28),
                _Blob(color: Neon.violet, alignment: Alignment(1.3 - t * .4, 1.2 - t * .3), size: 480, opacity: .26),
                _Blob(color: Neon.pink, alignment: Alignment(.6 - t * .6, .1 + t * .2), size: 260, opacity: .14),
              ],
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.alignment, required this.size, required this.opacity});

  final Color color;
  final Alignment alignment;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ecualizador de neón: las barras se mueven mientras suena música.
class NeonEqualizer extends StatefulWidget {
  const NeonEqualizer({super.key, required this.playing, this.height = 34});

  final bool playing;
  final double height;

  @override
  State<NeonEqualizer> createState() => _NeonEqualizerState();
}

class _NeonEqualizerState extends State<NeonEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(NeonEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const phases = [0.0, .2, .45, .7, .3];
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in phases)
              Container(
                width: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: widget.playing
                    ? 6 + (widget.height - 6) * (.5 + .5 * math.sin((_c.value + p) * 2 * math.pi)).abs()
                    : 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Neon.cyan, Neon.violet, Neon.pink],
                  ),
                  boxShadow: [BoxShadow(color: Neon.cyan.withValues(alpha: .5), blurRadius: 8)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Orbe del micrófono: anillo que gira y ondas mientras escucha.
class MicOrb extends StatefulWidget {
  const MicOrb({super.key, required this.on, required this.listening, required this.onTap, this.icon});

  final bool on;
  final bool listening;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.on && widget.listening;
    final core = active ? Neon.pink : Neon.cyan;
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            // Ondas cuando escucha.
            if (active)
              for (final d in const [0.0, .33, .66])
                Opacity(
                  opacity: math.max(0.0, math.min(1.0, 1 - ((_c.value + d) % 1))) * .8,
                  child: Container(
                    width: 100 + 50 * ((_c.value + d) % 1),
                    height: 100 + 50 * ((_c.value + d) % 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Neon.pink.withValues(alpha: .6), width: 2),
                    ),
                  ),
                ),
            // Anillo giratorio.
            Transform.rotate(
              angle: _c.value * 2 * math.pi * (active ? 2 : .5),
              child: Container(
                width: 132,
                height: 132,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [Colors.transparent, Neon.cyan, Colors.transparent, Neon.pink, Colors.transparent],
                    stops: [0, .2, .45, .7, 1],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Neon.space1),
                  ),
                ),
              ),
            ),
            // Núcleo.
            GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.35, -.35),
                    colors: widget.on
                        ? [Colors.white.withValues(alpha: .85), core, Neon.violet]
                        : [const Color(0xFF6B7A99), const Color(0xFF2A3350)],
                    stops: const [0, .45, 1],
                  ),
                  boxShadow: widget.on ? Neon.glow(core) : null,
                ),
                child: Icon(widget.icon ?? Icons.mic, size: 44, color: const Color(0xFF050616)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con degradado de neón (para «Sonando ahora»).
class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  Neon.cyan.withValues(alpha: .16),
                  Neon.violet.withValues(alpha: .14),
                  Neon.pink.withValues(alpha: .12),
                ]
              : [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.tertiaryContainer,
                ],
        ),
        border: Border.all(color: Neon.cyan.withValues(alpha: dark ? .3 : .15)),
        boxShadow: dark ? Neon.glow(Neon.cyan, .5) : null,
      ),
      child: child,
    );
  }
}
