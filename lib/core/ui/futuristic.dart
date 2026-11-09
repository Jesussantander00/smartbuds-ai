import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Identidad visual de SmartBuds: producto musical premium, claro y limpio.
///
/// Fondo #F4F6F8, tarjetas blancas, texto #17212B, verde petróleo #2F8F83
/// para acciones, menta #E3F3EF para superficies secundarias y naranja suave
/// #E6A85C solo para avisos y detalles (p. ej. «escuchando»).
///
/// Los nombres antiguos (`Neon.cyan`, `NeonCard`…) se mantienen para no
/// romper el resto de la app, pero ya no hay neón.
class Neon {
  /// Verde petróleo: color principal (botones, acciones, progreso).
  static const cyan = Color(0xFF2F8F83);

  /// Verde petróleo profundo (degradados de acciones importantes).
  static const violet = Color(0xFF1F6F66);

  /// Naranja suave: avisos y detalles («escuchando», batería baja).
  static const pink = Color(0xFFE6A85C);

  /// Texto principal.
  static const ink = Color(0xFF17212B);

  /// Fondo de la app.
  static const space0 = Color(0xFFF4F6F8);
  static const space1 = Color(0xFFFFFFFF);

  /// Tarjetas y superficies secundarias.
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFE3F3EF);

  /// Modo oscuro opcional, misma identidad.
  static const darkBg = Color(0xFF0F1518);
  static const darkCard = Color(0xFF172026);
  static const darkPrimary = Color(0xFF4DB6A9);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, violet],
  );

  /// Sombra suave de tarjeta.
  static List<BoxShadow> glow([Color color = ink, double strength = 1]) => [
        BoxShadow(
          color: color.withValues(alpha: .06 * strength),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

ThemeData smartBudsTheme(Brightness brightness, Color seed) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? Neon.darkPrimary : Neon.cyan;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: seed == Neon.cyan ? primary : null,
    surface: dark ? Neon.darkCard : Neon.surface,
    onSurface: dark ? const Color(0xFFE7ECEF) : Neon.ink,
    secondaryContainer: dark ? const Color(0xFF1E3A36) : Neon.surfaceHigh,
    tertiary: Neon.pink,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final bg = dark ? Neon.darkBg : Neon.space0;
  final line = dark ? Colors.white.withValues(alpha: .08) : const Color(0xFFE3E8EC);
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : scheme.onSurfaceVariant),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? primary : scheme.onSurfaceVariant,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surface,
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerColor: line,
    dividerTheme: DividerThemeData(color: line),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: primary,
      inactiveTrackColor: primary.withValues(alpha: .15),
      thumbColor: primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
  );
}

/// Fondo de la app: color liso, sin auroras (se mantiene por compatibilidad).
class SpaceBackground extends StatelessWidget {
  const SpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: child);
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
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w / 2),
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón del micrófono: círculo verde petróleo; mientras escucha, ondas
/// suaves en naranja. Apagado: gris claro.
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
                  opacity: (1 - ((_c.value + d) % 1)) * .55,
                  child: Container(
                    width: core + (widget.size - core) * ((_c.value + d) % 1),
                    height: core + (widget.size - core) * ((_c.value + d) % 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Neon.pink.withValues(alpha: .35),
                    ),
                  ),
                ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              elevation: widget.on ? 6 : 1,
              shadowColor: Neon.cyan.withValues(alpha: .4),
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
                    color: widget.on ? null : scheme.surfaceContainerHighest,
                    border: active ? Border.all(color: Neon.pink, width: 3) : null,
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

/// Tarjeta principal: blanca, bordes suaves y sombra discreta.
class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
        boxShadow: dark ? null : Neon.glow(),
      ),
      child: child,
    );
  }
}
