import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import 'self_check.dart';

/// Autodiagnóstico: qué funciona, qué no, qué pasó y cómo resolverlo.
class SelfCheckScreen extends StatefulWidget {
  const SelfCheckScreen({super.key, required this.assistant, this.onOpenPermissions});
  final Assistant assistant;
  final Future<void> Function()? onOpenPermissions;

  @override
  State<SelfCheckScreen> createState() => _SelfCheckScreenState();
}

class _SelfCheckScreenState extends State<SelfCheckScreen> {
  List<Finding>? _findings;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final f = await widget.assistant.selfCheck();
    if (!mounted) return;
    setState(() {
      _findings = f;
      _running = false;
    });
  }

  Future<void> _fix(FixAction a) async {
    final voice = widget.assistant.voice;
    switch (a) {
      case FixAction.retryVoice:
        await voice?.retry();
      case FixAction.enableVoice:
        await voice?.start();
      case FixAction.openAppSettings:
        await voice?.openAppSettings();
      case FixAction.openNotificationAccess:
        await widget.onOpenPermissions?.call();
      case FixAction.refreshHeadphones:
        await widget.assistant.refreshHeadphone();
      case FixAction.none:
        return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) await _run();
  }

  static String _label(FixAction a) => switch (a) {
        FixAction.retryVoice => 'Reintentar',
        FixAction.enableVoice => 'Encender',
        FixAction.openAppSettings => 'Abrir ajustes',
        FixAction.openNotificationAccess => 'Dar permiso',
        FixAction.refreshHeadphones => 'Revisar otra vez',
        FixAction.none => '',
      };

  static (IconData, String) _area(CheckArea a) => switch (a) {
        CheckArea.voz => (Icons.mic_rounded, 'Voz'),
        CheckArea.permisos => (Icons.verified_user_rounded, 'Permisos'),
        CheckArea.reproduccion => (Icons.play_circle_rounded, 'Reproducción'),
        CheckArea.conexion => (Icons.wifi_rounded, 'Conexión'),
        CheckArea.audifonos => (Icons.headphones_rounded, 'Audífonos'),
        CheckArea.bateria => (Icons.battery_alert_rounded, 'Batería'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final findings = _findings;
    final voice = widget.assistant.voice;
    final problems = findings?.where((f) => f.severity == Severity.problem).length ?? 0;
    final warnings = findings?.where((f) => f.severity == Severity.warning).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autodiagnóstico'),
        actions: [
          IconButton(
            tooltip: 'Revisar otra vez',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: findings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Glass(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        problems > 0
                            ? Icons.error_rounded
                            : warnings > 0
                                ? Icons.info_rounded
                                : Icons.check_circle_rounded,
                        size: 40,
                        color: problems > 0 ? Neon.pink : (warnings > 0 ? Colors.amber : const Color(0xFF22C55E)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          problems > 0
                              ? '$problems problema${problems == 1 ? '' : 's'} para resolver'
                              : warnings > 0
                                  ? 'Funciona, con $warnings cosa${warnings == 1 ? '' : 's'} por revisar'
                                  : 'Todo funciona bien',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final f in findings) _tile(theme, f),
                if (voice != null && voice.diagnostics.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                    child: Text('Lo que pasó con la escucha', style: theme.textTheme.titleSmall),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final d in voice.diagnostics.take(12))
                          ListTile(
                            dense: true,
                            leading: Text(TimeOfDay.fromDateTime(d.at).format(context),
                                style: theme.textTheme.labelSmall),
                            title: Text(d.what),
                          ),
                      ],
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'El autodiagnóstico solo mira el estado de la app en este teléfono. No envía nada; '
                    'para enviarnos un reporte usa «Enviar un reporte» en Privacidad.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(ThemeData theme, Finding f) {
    final (icon, area) = _area(f.area);
    final color = switch (f.severity) {
      Severity.ok => const Color(0xFF22C55E),
      Severity.warning => Colors.amber,
      Severity.problem => Neon.pink,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(area.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: color)),
              ],
            ),
            const SizedBox(height: 6),
            Text(f.title, style: theme.textTheme.titleSmall),
            if (f.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Qué pasó: ${f.detail}', style: theme.textTheme.bodyMedium),
            ],
            if (f.fix.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Cómo resolverlo: ${f.fix}', style: theme.textTheme.bodyMedium),
            ],
            if (f.action != FixAction.none && !f.isOk)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(onPressed: () => _fix(f.action), child: Text(_label(f.action))),
              ),
          ],
        ),
      ),
    );
  }
}
