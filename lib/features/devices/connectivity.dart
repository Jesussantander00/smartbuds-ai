import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';
import 'detected_player_controller.dart';

/// Conexión de tus audífonos: historial, diagnóstico de inestabilidad,
/// prueba de respuesta y solución de problemas.
class ConnectivityCard extends StatefulWidget {
  const ConnectivityCard({
    super.key,
    required this.assistant,
    required this.controller,
    this.voice,
    this.onOpenPermissions,
  });

  final Assistant assistant;
  final DetectedPlayerController controller;
  final VoiceEngine? voice;
  final Future<void> Function()? onOpenPermissions;

  @override
  State<ConnectivityCard> createState() => _ConnectivityCardState();
}

class _ConnectivityCardState extends State<ConnectivityCard> {
  bool _testing = false;
  String? _latency;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _latency = null;
    });
    final ms = await widget.assistant.measureLatency();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _latency = ms == null
          ? 'El reproductor no respondió. Abre «Solucionar problemas».'
          : 'Respondió en $ms ms ${ms < 400 ? '· excelente' : ms < 1000 ? '· normal' : '· lento'}';
    });
  }

  static String _time(BuildContext context, DateTime at) {
    final now = DateTime.now();
    final t = TimeOfDay.fromDateTime(at).format(context);
    if (now.difference(at).inDays == 0 && now.day == at.day) return t;
    return '${at.day}/${at.month} $t';
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.assistant.settings;
    if (settings == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final log = settings.connectionLog;
        final unstable = settings.unstableConnection(DateTime.now());
        return NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppIcon(Icons.bluetooth_rounded, colors: AppColors.assistant, size: 36),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Conexión', style: theme.textTheme.titleMedium)),
                ],
              ),
              if (unstable)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Neon.pink.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Neon.pink),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Tus audífonos se desconectaron varias veces en 15 minutos. '
                            'Acércalos al teléfono, revisa su batería o vuelve a emparejarlos.'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (log.isEmpty)
                Text('Aún no hay conexiones registradas.', style: theme.textTheme.bodySmall)
              else
                for (final e in log.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e.connected ? Icons.link_rounded : Icons.link_off_rounded,
                      color: e.connected ? const Color(0xFF22C55E) : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text('${e.connected ? 'Conectados' : 'Desconectados'}'
                        '${e.name == null ? '' : ' · ${e.name}'}'),
                    trailing: Text(_time(context, e.at), style: theme.textTheme.labelSmall),
                  ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing || widget.assistant.active == null ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.speed_rounded),
                    label: const Text('Probar respuesta'),
                  ),
                  FilledButton.icon(
                    onPressed: () => showTroubleshooter(
                      context,
                      assistant: widget.assistant,
                      controller: widget.controller,
                      voice: widget.voice,
                      onOpenPermissions: widget.onOpenPermissions,
                    ),
                    icon: const Icon(Icons.healing_rounded),
                    label: const Text('Solucionar problemas'),
                  ),
                ],
              ),
              if (_latency != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_latency!, style: theme.textTheme.bodyMedium),
                ),
              if (widget.assistant.active == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Para probar la respuesta pon música primero.', style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Un paso del diagnóstico.
class _Check {
  const _Check(this.ok, this.title, this.okText, this.fixText, {this.fix, this.fixLabel});
  final bool ok;
  final String title;
  final String okText;
  final String fixText;
  final VoidCallback? fix;
  final String? fixLabel;
}

/// Asistente de solución de problemas: revisa permisos, reproductor,
/// micrófono, audífonos y controles, y ofrece el arreglo de cada uno.
Future<void> showTroubleshooter(
  BuildContext context, {
  required Assistant assistant,
  required DetectedPlayerController controller,
  VoiceEngine? voice,
  Future<void> Function()? onOpenPermissions,
}) async {
  final access = (await assistant.media?.missingPermission()) == null;
  if (!context.mounted) return;
  final detection = controller.detection;
  final player = detection is PlayerDetected ? detection.candidate : null;
  final view = player == null
      ? null
      : controller.players.where((p) => p.status.playerId == player.status.playerId).firstOrNull;
  final settings = assistant.settings;
  final checks = [
    _Check(
      access,
      'Permiso para ver la música',
      'SmartBuds puede ver qué suena.',
      'Sin el acceso a notificaciones SmartBuds no ve ni controla tus apps de música.',
      fix: onOpenPermissions == null ? null : () => onOpenPermissions(),
      fixLabel: 'Dar permiso',
    ),
    _Check(
      player != null,
      'Reproductor',
      player == null ? '' : '${player.status.appName} está abierto.',
      'No hay música abierta. Abre tu app de música y pon una canción (aunque sea en pausa).',
    ),
    _Check(
      view == null || view.voiceCaps.level == ControlLevel.direct,
      'Controles',
      'Siguiente, pausa y volumen funcionan directo.',
      'Esta app limita algunos controles. Prueba con YouTube Music o Spotify.',
    ),
    _Check(
      voice == null || (voice.enabled && voice.error == null),
      'Micrófono',
      'SmartBuds te está escuchando.',
      voice?.error ?? 'El micrófono está apagado.',
      fix: voice == null || voice.enabled ? null : voice.toggle,
      fixLabel: 'Encender',
    ),
    _Check(
      assistant.headphoneName != null,
      'Audífonos',
      'Conectados: ${assistant.headphoneName ?? ''}.',
      'No veo audífonos. Si usas Bluetooth, revisa que estén encendidos y emparejados.',
      fix: assistant.refreshHeadphone,
      fixLabel: 'Revisar otra vez',
    ),
    _Check(
      settings == null || !settings.unstableConnection(DateTime.now()),
      'Estabilidad',
      'La conexión de los audífonos está estable.',
      'Se desconectan seguido: acércalos, cárgalos o vuelve a emparejarlos.',
    ),
  ];
  final bad = checks.where((c) => !c.ok).length;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Solucionar problemas', style: theme.textTheme.titleLarge),
              Text(bad == 0 ? 'Todo se ve bien.' : '$bad cosa${bad == 1 ? '' : 's'} por revisar.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final c in checks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: c.ok ? const Color(0xFF22C55E) : Neon.pink,
                  ),
                  title: Text(c.title),
                  subtitle: Text(c.ok ? c.okText : c.fixText),
                  trailing: !c.ok && c.fix != null
                      ? TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            c.fix!();
                          },
                          child: Text(c.fixLabel ?? 'Arreglar'),
                        )
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Estrella para marcar los audífonos conectados como preferidos.
class PreferredHeadphoneButton extends StatelessWidget {
  const PreferredHeadphoneButton({super.key, required this.settings, required this.name});
  final AppSettings settings;
  final String name;

  @override
  Widget build(BuildContext context) {
    final on = settings.preferredHeadphone == name;
    return IconButton(
      tooltip: on ? 'Quitar de preferidos' : 'Marcar como preferidos',
      icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, color: on ? Neon.cyan : null),
      onPressed: () => settings.setPreferredHeadphone(on ? null : name),
    );
  }
}
