import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';
import '../devices/detected_player_controller.dart';
import '../privacy/changelog.dart';
import '../social/social_service.dart';

/// Una sección de la app en la barra lateral.
class SidebarItem {
  const SidebarItem(this.label, this.icon, this.colors);
  final String label;
  final IconData icon;
  final List<Color> colors;
}

const sidebarItems = [
  SidebarItem('Inicio', Icons.home_rounded, AppColors.home),
  SidebarItem('Asistente', Icons.mic_rounded, AppColors.assistant),
  SidebarItem('Mi música', Icons.favorite_rounded, AppColors.music),
  SidebarItem('Amigos', Icons.group_rounded, AppColors.radio),
  SidebarItem('Dispositivos', Icons.headphones_rounded, AppColors.devices),
  SidebarItem('Privacidad y ayuda', Icons.shield_rounded, AppColors.stats),
];

/// Barra lateral de vidrio: compacta (solo iconos) o abierta (con nombres,
/// mini reproductor, modo noche y tu cuenta).
class GlassSidebar extends StatelessWidget {
  const GlassSidebar({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.selected,
    required this.onSelect,
    required this.assistant,
    required this.controller,
    required this.settings,
    this.voice,
    this.social,
  });

  final SocialService? social;

  final bool expanded;
  final VoidCallback onToggle;
  final int selected;
  final ValueChanged<int> onSelect;
  final Assistant assistant;
  final DetectedPlayerController controller;
  final AppSettings settings;
  final VoiceEngine? voice;

  static const collapsedWidth = 76.0;
  static const expandedWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [assistant, controller, settings, if (voice != null) voice!, if (social != null) social!]),
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: expanded ? expandedWidth : collapsedWidth,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Glass(
                radius: expanded ? 32 : 38,
                padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 8, vertical: 14),
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: IntrinsicHeight(
                        child: expanded && c.maxWidth > 200 ? _expanded(context) : _collapsed(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Botón para abrir / cerrar (sobresale del borde, como en macOS).
            Positioned(
              right: -14,
              top: 22,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onToggle,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                      size: 20,
                      color: Neon.ink,
                      semanticLabel: expanded ? 'Cerrar menú' : 'Abrir menú',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PlayerStatus? get _status => assistant.active;

  /// Novedades que aún no has visto.
  int get _unseen => changelog.where((c) => c.version > settings.lastSeenChangelog).length;
  bool get _listening => (voice?.enabled ?? false) && (voice?.listening ?? false) && !(voice?.paused ?? false);

  Future<void> _search(BuildContext context) async {
    final ctrl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Qué quieres escuchar?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => Navigator.pop(c, v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Canción, artista, «música de los 80»…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Buscar')),
        ],
      ),
    );
    ctrl.dispose();
    if (q != null && q.trim().isNotEmpty) {
      await assistant.handleSearch(SearchRequest(CommandParser.refineQuery(q.trim())));
    }
  }

  // ------------------------------------------------------------- Compacta

  Widget _collapsed(BuildContext context) {
    final s = _status;
    return Column(
      children: [
        const AppIcon(Icons.headphones_rounded, colors: [Color(0xFF6B4A3A), Color(0xFF3B2A22)], size: 44),
        const SizedBox(height: 10),
        _RailButton(
          tooltip: 'Buscar',
          onTap: () => _search(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.search_rounded, color: Neon.ink, size: 22),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, indent: 14, endIndent: 14, color: Neon.ink.withValues(alpha: .1)),
        ),
        for (var i = 0; i < sidebarItems.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Punto que marca la sección abierta.
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == selected ? Neon.ink : Colors.transparent,
                  ),
                ),
                _RailButton(
                  tooltip: sidebarItems[i].label,
                  onTap: () => onSelect(i),
                  child: AnimatedScale(
                    scale: i == selected ? 1.08 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: AppIcon(
                      sidebarItems[i].icon,
                      colors: sidebarItems[i].colors,
                      badge: switch (i) {
                        0 => assistant.queue.length,
                        3 => social?.unseen,
                        5 => _unseen,
                        _ => null,
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        const Spacer(),
        if (s != null && (s.title ?? '').isNotEmpty)
          _RailButton(
            tooltip: s.isPlaying ? 'Pausa' : 'Reproducir',
            onTap: () => controller.send(MusicCommand.togglePlayPause),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    value: s.progress ?? 0,
                    strokeWidth: 2.5,
                    color: Neon.cyan,
                    backgroundColor: Neon.ink.withValues(alpha: .08),
                  ),
                ),
                ClipOval(
                  child: s.art != null
                      ? Image.memory(s.art!, width: 38, height: 38, fit: BoxFit.cover, gaplessPlayback: true)
                      : Container(
                          width: 38,
                          height: 38,
                          color: const Color(0xFF2A2420),
                          child: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Neon.cyan),
                        ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        _RailButton(
          tooltip: settings.themeMode == 'dark' ? 'Modo claro' : 'Modo noche',
          onTap: () => settings.update(themeMode: settings.themeMode == 'dark' ? 'light' : 'dark'),
          child: AppIcon(
            settings.themeMode == 'dark' ? Icons.light_mode_rounded : Icons.nightlight_round,
            colors: AppColors.night,
          ),
        ),
        const SizedBox(height: 10),
        _Avatar(settings: settings, listening: _listening),
      ],
    );
  }

  // --------------------------------------------------------------- Abierta

  Widget _expanded(BuildContext context) {
    final theme = Theme.of(context);
    final s = _status;
    final label = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppIcon(Icons.headphones_rounded, colors: [Color(0xFF6B4A3A), Color(0xFF3B2A22)], size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SmartBuds', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Tu música por voz', style: label),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(gradient: Neon.gradient, borderRadius: BorderRadius.circular(10)),
              child: const Text('AI',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            ),
            const SizedBox(width: 10),
          ],
        ),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _search(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .7)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text('Buscar música', style: label?.copyWith(fontSize: 14))),
                Icon(Icons.mic_none_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Text('Secciones', style: label)),
        for (var i = 0; i < sidebarItems.length; i++)
          _Row(
            icon: AppIcon(sidebarItems[i].icon, colors: sidebarItems[i].colors, size: 36),
            label: sidebarItems[i].label,
            selected: i == selected,
            onTap: () => onSelect(i),
            trailing: switch (i) {
              0 => assistant.queue.isEmpty ? null : _Count(assistant.queue.length),
              1 => _listening ? const _Pill('Escuchando', dot: true) : null,
              3 => (social?.unseen ?? 0) > 0 ? _Count(social!.unseen) : null,
              4 => assistant.headphoneName == null ? null : const Icon(Icons.bluetooth_connected, size: 18),
              5 => settings.privateMode
                  ? const _Pill('Privado')
                  : _unseen > 0
                      ? const _Pill('Nuevo', dot: true)
                      : null,
              _ => null,
            },
          ),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Text('Rápido', style: label)),
        _Row(
          icon: const AppIcon(Icons.radio_rounded, colors: AppColors.radio, size: 36),
          label: 'Mi radio',
          onTap: () => assistant.setRadio(!settings.radioMode),
          trailing: Switch(value: settings.radioMode, onChanged: (v) => assistant.setRadio(v)),
        ),
        const Spacer(),
        const SizedBox(height: 12),
        if (s != null && (s.title ?? '').isNotEmpty) _MiniPlayer(status: s, controller: controller),
        const SizedBox(height: 8),
        _Row(
          icon: const AppIcon(Icons.nightlight_round, colors: AppColors.night, size: 36),
          label: 'Modo noche',
          onTap: () => settings.update(themeMode: settings.themeMode == 'dark' ? 'light' : 'dark'),
          trailing: Switch(
            value: settings.themeMode == 'dark',
            onChanged: (v) => settings.update(themeMode: v ? 'dark' : 'light'),
          ),
        ),
        Divider(height: 18, color: Neon.ink.withValues(alpha: .1)),
        Row(
          children: [
            _Avatar(settings: settings, listening: _listening),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(settings.signedIn ? 'Tu cuenta' : 'Sin cuenta',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    settings.authEmail ?? 'Entra en Mi música para guardar tus gustos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.tooltip, required this.onTap, required this.child});
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: child),
        ),
      );
}

/// Fila de la barra abierta; la seleccionada se ve como una pastilla blanca.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.selected = false, this.trailing});
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? LinearGradient(colors: [
                      Colors.white.withValues(alpha: .9),
                      const Color(0xFFFBE5D2).withValues(alpha: .8),
                    ])
                  : null,
              boxShadow: selected
                  ? [BoxShadow(color: Neon.ink.withValues(alpha: .08), blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Neon.ink : null)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Neon.pink, borderRadius: BorderRadius.circular(10)),
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.dot = false});
  final String text;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Neon.cyan.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Neon.cyan),
              ),
            Text(text, style: const TextStyle(color: Neon.violet, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.settings, required this.listening});
  final AppSettings settings;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final email = settings.authEmail;
    final initial = (email == null || email.isEmpty) ? null : email[0].toUpperCase();
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFFFFE0C2), Color(0xFFF3B88A)]),
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: initial == null
                ? const Icon(Icons.person_rounded, color: Color(0xFF6B4A3A))
                : Text(initial,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B4A3A), fontSize: 18)),
          ),
          // Punto verde: sesión iniciada; naranja: escuchando.
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening
                    ? Neon.cyan
                    : settings.signedIn
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFB8ADA4),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini reproductor de vidrio: carátula, título, ecualizador, ⏮ ⏯ ⏭ y progreso.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.status, required this.controller});
  final PlayerStatus status;
  final DetectedPlayerController controller;

  static String _fmt(int ms) {
    final t = Duration(milliseconds: ms);
    return '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final d = s.durationMs, p = s.positionMs;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .8)),
        boxShadow: [BoxShadow(color: Neon.ink.withValues(alpha: .06), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: s.art != null
                    ? Image.memory(s.art!, width: 44, height: 44, fit: BoxFit.cover, gaplessPlayback: true)
                    : Container(
                        width: 44,
                        height: 44,
                        color: const Color(0xFF2A2420),
                        child: const Icon(Icons.album_rounded, color: Neon.cyan),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700, color: Neon.ink)),
                        ),
                        if (s.isPlaying) ...[
                          const SizedBox(width: 6),
                          const NeonEqualizer(playing: true, height: 12),
                        ],
                      ],
                    ),
                    Text(s.artist ?? s.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: Neon.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Anterior',
                color: Neon.ink,
                onPressed: () => controller.send(MusicCommand.previous),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 4),
              Material(
                shape: const CircleBorder(),
                color: Colors.transparent,
                child: Ink(
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Neon.gradient),
                  child: IconButton(
                    tooltip: s.isPlaying ? 'Pausa' : 'Reproducir',
                    color: Colors.white,
                    onPressed: () => controller.send(MusicCommand.togglePlayPause),
                    icon: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Siguiente',
                color: Neon.ink,
                onPressed: () => controller.send(MusicCommand.next),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          if (d != null && d > 0 && p != null)
            Row(
              children: [
                Text(_fmt(p), style: theme.textTheme.labelSmall?.copyWith(color: Neon.inkSoft)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: s.progress ?? 0,
                      minHeight: 4,
                      color: Neon.cyan,
                      backgroundColor: Neon.ink.withValues(alpha: .1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('-${_fmt(d - p < 0 ? 0 : d - p)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: Neon.inkSoft)),
              ],
            ),
        ],
      ),
    );
  }
}
