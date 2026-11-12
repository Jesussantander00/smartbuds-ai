import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'live_visuals.dart';

/// Identidad «vidrio cálido» de SmartBuds: paneles de vidrio esmerilado sobre
/// un fondo beige con luz suave, iconos de colores tipo app y un naranja
/// cálido para la acción principal (reproducir).
///
/// Los nombres antiguos (`Neon.cyan`, `NeonCard`…) se mantienen para no
/// romper el resto de la app.
class Neon {
  /// Acción principal: naranja cálido.
  static const cyan = Color(0xFFE8833A);

  /// Naranja profundo (degradado de la acción principal).
  static const violet = Color(0xFFD9652A);

  /// Detalles y avisos («escuchando», insignias).
  static const pink = Color(0xFFE5484D);

  /// Texto principal (café muy oscuro).
  static const ink = Color(0xFF2A2420);
  static const inkSoft = Color(0xFF7A6E66);

  /// Fondo: beige cálido.
  static const space0 = Color(0xFFE8E0D8);
  static const space1 = Color(0xFFD6CABF);

  /// Vidrio.
  static const surface = Color(0xFFF6F1EC);
  static const surfaceHigh = Color(0xFFFFFFFF);

  /// Modo noche: café oscuro con el mismo vidrio.
  static const darkBg = Color(0xFF1C1815);
  static const darkCard = Color(0xFF2A241F);
  static const darkPrimary = Color(0xFFF29A4A);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A055), violet],
  );

  /// Sombra suave de panel.
  static List<BoxShadow> glow([Color color = ink, double strength = 1]) => [
        BoxShadow(
          color: color.withValues(alpha: .10 * strength),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}

/// Colores de los iconos tipo app (como los de iOS / macOS).
class AppColors {
  static const home = [Color(0xFFFF9F52), Color(0xFFF26A2E)];
  static const assistant = [Color(0xFF5AA9FF), Color(0xFF2F6FE4)];
  static const music = [Color(0xFFFF7A9C), Color(0xFFE5484D)];
  static const devices = [Color(0xFFA78BFA), Color(0xFF7C4DFF)];
  static const stats = [Color(0xFF5EDBB7), Color(0xFF1FA889)];
  static const night = [Color(0xFF7CC4FF), Color(0xFF3B82F6)];
  static const radio = [Color(0xFFFFC857), Color(0xFFF59E0B)];
}

ThemeData smartBudsTheme(Brightness brightness, Color seed) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? Neon.darkPrimary : Neon.cyan;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: seed == Neon.cyan ? primary : null,
    surface: dark ? Neon.darkCard : Neon.surface,
    onSurface: dark ? const Color(0xFFF1EBE5) : Neon.ink,
    onSurfaceVariant: dark ? const Color(0xFFB9ADA3) : Neon.inkSoft,
    secondaryContainer: dark ? const Color(0xFF3A3029) : const Color(0xFFF3E6DA),
    tertiary: Neon.pink,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final line = dark ? Colors.white.withValues(alpha: .08) : Colors.white.withValues(alpha: .7);
  final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: dark ? Neon.darkBg : Neon.space0,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: (dark ? Neon.darkCard : Colors.white).withValues(alpha: dark ? .7 : .55),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: (dark ? Neon.darkCard : Colors.white).withValues(alpha: .6),
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: dark ? Colors.white.withValues(alpha: .08) : Neon.ink.withValues(alpha: .08),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : scheme.onSurface.withValues(alpha: .15)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: primary,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: .12),
      thumbColor: primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: (dark ? Colors.black : Colors.white).withValues(alpha: .35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: line)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: line)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primary, width: 1.5)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Fondo cálido con luces suaves, como una sala iluminada.
class SpaceBackground extends StatelessWidget {
  const SpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF2A231E), Neon.darkBg]
              : const [Color(0xFFEFE8E1), Color(0xFFDCD0C5)],
        ),
      ),
      child: ValueListenableBuilder<Color?>(
        // Ambiente visual automático: la luz de fondo toma el color de la carátula.
        valueListenable: ArtAmbient.color,
        builder: (context, art, _) => Stack(
          children: [
            _Light(alignment: const Alignment(-.9, -.8), color: dark ? const Color(0xFF6B4A2E) : Colors.white),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: _Light(
                key: ValueKey(art),
                alignment: const Alignment(1, .5),
                color: art ?? (dark ? const Color(0xFF4A3424) : const Color(0xFFFFE3C4)),
              ),
            ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({super.key, required this.alignment, required this.color});
  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: IgnorePointer(
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color.withValues(alpha: .55), color.withValues(alpha: 0)]),
            ),
          ),
        ),
      );
}

/// Panel de vidrio esmerilado (desenfoca lo que hay detrás).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.opacity = .5,
    this.blur = 24,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double opacity;
  final double blur;

  /// Color suave que tiñe el vidrio (p. ej. el de la carátula).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: Neon.glow()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tint != null
                    ? [tint!.withValues(alpha: dark ? .30 : .38), Colors.white.withValues(alpha: dark ? .05 : opacity - .1)]
                    : dark
                        ? [Colors.white.withValues(alpha: .10), Colors.white.withValues(alpha: .04)]
                        : [Colors.white.withValues(alpha: opacity + .15), Colors.white.withValues(alpha: opacity - .15)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: dark ? .12 : .75), width: 1.2),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Icono tipo app: cuadrado redondeado con degradado y brillo.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, required this.colors, this.size = 40, this.badge});

  final IconData icon;
  final List<Color> colors;
  final double size;

  /// Número rojo en la esquina (null = sin insignia).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .28),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
              boxShadow: [
                BoxShadow(color: colors.last.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Stack(
              children: [
                // Brillo superior.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: size * .5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(size * .28)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withValues(alpha: .35), Colors.white.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Center(child: Icon(icon, color: Colors.white, size: size * .52)),
              ],
            ),
          ),
          if (badge != null && badge! > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: Neon.pink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  badge! > 99 ? '99+' : '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ecualizador discreto: barras que se mueven mientras suena música.
class NeonEqualizer extends StatefulWidget {
  const NeonEqualizer({super.key, required this.playing, this.height = 34, this.color});

  final bool playing;
  final double height;
  final Color? color;

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
    final color = widget.color ?? Neon.cyan;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = (widget.height / 7).clamp(2.0, 6.0).toDouble();
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
                width: w,
                margin: EdgeInsets.symmetric(horizontal: w * .3),
                height: widget.playing && !reduce
                    ? w + (widget.height - w) * (.5 + .5 * math.sin((_c.value + p) * 2 * math.pi)).abs()
                    : (widget.playing ? widget.height * .6 : w),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(w / 2), color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón del micrófono: naranja cálido; mientras escucha, ondas suaves.
class MicOrb extends StatefulWidget {
  const MicOrb({
    super.key,
    required this.on,
    required this.listening,
    required this.onTap,
    this.icon,
    this.size = 150,
  });

  final double size;
  final bool on;
  final bool listening;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.on && widget.listening;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final core = widget.size * .62;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (active && !reduce)
              for (final d in const [0.0, .5])
                Opacity(
                  opacity: (1 - ((_c.value + d) % 1)) * .5,
                  child: Container(
                    width: core + (widget.size - core) * ((_c.value + d) % 1),
                    height: core + (widget.size - core) * ((_c.value + d) % 1),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Neon.cyan.withValues(alpha: .35)),
                  ),
                ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              elevation: widget.on ? 8 : 2,
              shadowColor: Neon.violet.withValues(alpha: .5),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: core,
                  height: core,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.on ? Neon.gradient : null,
                    color: widget.on ? null : Colors.white.withValues(alpha: .7),
                    border: Border.all(color: Colors.white.withValues(alpha: .8), width: 2),
                  ),
                  child: Icon(
                    widget.icon ?? Icons.mic,
                    size: core * .42,
                    color: widget.on ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta principal: un panel de vidrio.
class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.tint});

  final Widget child;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Glass(padding: padding, tint: tint, child: child),
      );
}
