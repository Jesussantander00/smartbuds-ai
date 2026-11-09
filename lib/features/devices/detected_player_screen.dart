import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import 'detected_player_controller.dart';
import 'connectivity.dart';

class DetectedPlayerScreen extends StatefulWidget {
  const DetectedPlayerScreen({
    super.key,
    required this.controller,
    this.voice,
    this.onOpenPermissions,
    this.platformNote,
    this.assistant,
  });

  /// Audífonos, ajustes rápidos (opcional; null en pruebas).
  final Assistant? assistant;

  final DetectedPlayerController controller;

  /// Motor de voz; null en plataformas sin reconocimiento (y en pruebas).
  final VoiceEngine? voice;
  final Future<void> Function()? onOpenPermissions;

  /// Aviso de plataforma (p. ej. limitaciones de iOS).
  final String? platformNote;

  @override
  State<DetectedPlayerScreen> createState() => _DetectedPlayerScreenState();
}

class _DetectedPlayerScreenState extends State<DetectedPlayerScreen>
    with WidgetsBindingObserver {
  DetectedPlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de Ajustes, comprobar de nuevo el permiso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Dispositivos'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: c.refresh,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
            children: [
              if (widget.platformNote != null)
                _Banner(icon: Icons.info_outline, text: widget.platformNote!),
              for (final msg in c.missingPermissions.values)
                _Banner(
                  icon: Icons.lock_outline,
                  text: msg,
                  action: widget.onOpenPermissions == null
                      ? null
                      : TextButton(
                          onPressed: widget.onOpenPermissions,
                          child: const Text('Conceder acceso'),
                        ),
                ),
              if (widget.assistant != null) ...[
                _HeadphonesCard(assistant: widget.assistant!),
                ConnectivityCard(
                  assistant: widget.assistant!,
                  controller: c,
                  voice: widget.voice ?? widget.assistant!.voice,
                  onOpenPermissions: widget.onOpenPermissions,
                ),
                const SizedBox(height: 12),
              ],
              _DetectionCard(controller: c),
              const SizedBox(height: 12),
              if (widget.voice != null) ...[
                _VoiceBar(voice: widget.voice!),
                const SizedBox(height: 12),
              ],
              Text('Tus apps de música', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (c.players.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No hay música abierta. Abre tu app de música y pon algo: '
                    'aparecerá aquí sola.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final p in c.players)
                Card(
                  child: ListTile(
                    leading: Icon(p.status.isPlaying
                        ? Icons.graphic_eq
                        : Icons.pause_circle_outline),
                    title: Text(p.status.appName),
                    subtitle: Text(p.status.title == null
                        ? (p.status.isPlaying ? 'Sonando' : 'En pausa')
                        : '${p.status.title}${p.status.artist == null ? '' : ' — ${p.status.artist}'}'),
                    trailing: Icon(
                      p.voiceCaps.level == ControlLevel.direct
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: p.voiceCaps.level == ControlLevel.direct
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Avanzado'),
                  subtitle: const Text('Pruebas, capacidades y registro'),
                  childrenPadding: const EdgeInsets.all(8),
                  children: [
                    _TestControls(controller: c),
                    if (c.lastResult != null) _ResultTile(result: c.lastResult!),
                    const SizedBox(height: 12),
                    for (final p in c.players) _PlayerTile(view: p, controller: c),
                    const SizedBox(height: 12),
                    _CapabilityLog(controller: c),
                  ],
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tus audífonos, destacados: conexión, último usado y ajustes rápidos.
class _HeadphonesCard extends StatelessWidget {
  const _HeadphonesCard({required this.assistant});
  final Assistant assistant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([assistant, if (assistant.settings != null) assistant.settings!]),
      builder: (context, _) {
        final s = assistant.settings;
        final name = assistant.headphoneName;
        final connected = name != null;
        final saved = name == null ? null : s?.headphoneVolumes[name];
        return NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: connected ? Neon.gradient : null,
                      color: connected ? null : theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Icon(connected ? Icons.headphones : Icons.headset_off,
                        size: 32, color: connected ? Colors.white : theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name ?? 'Sin audífonos',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected ? Neon.cyan : theme.colorScheme.outline,
                              ),
                            ),
                            Text(connected ? 'Conectados' : 'Desconectados',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                        if (!connected && s?.lastHeadphone != null)
                          Text('Últimos usados: ${s!.lastHeadphone}', style: theme.textTheme.bodySmall),
                        if (saved != null)
                          Text('Volumen guardado: $saved %', style: theme.textTheme.bodySmall),
                        if (s?.preferredHeadphone != null)
                          Text(
                              s!.preferredHeadphone == name
                                  ? '★ Tus audífonos preferidos'
                                  : 'Preferidos: ${s.preferredHeadphone}',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (name != null && s != null) PreferredHeadphoneButton(settings: s, name: name),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: const Icon(Icons.refresh),
                    onPressed: assistant.refreshHeadphone,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'La batería de cada audífono y del estuche solo la muestra la app del '
                'fabricante: Android no la comparte con otras apps.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (s != null) ...[
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Pausar al quitarlos'),
                  value: s.pauseOnUnplug,
                  onChanged: (v) {
                    s.update(pauseOnUnplug: v);
                    assistant.media?.setPauseOnUnplug(v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Retomar al conectarlos'),
                  value: s.resumeOnHeadphones,
                  onChanged: (v) => s.update(resumeOnHeadphones: v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Dos toques = siguiente'),
                  value: s.headphoneTaps,
                  onChanged: (v) {
                    s.update(headphoneTaps: v);
                    assistant.media?.setTapGestures(v);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(leading: Icon(icon), title: Text(text), trailing: action),
      );
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.controller});
  final DetectedPlayerController controller;

  static String reasonText(DetectionReason r) => switch (r) {
        DetectionReason.playing => 'Está reproduciendo audio',
        DetectionReason.recentlyActive => 'Estuvo activo hace poco',
        DetectionReason.lastUsed => 'Último reproductor utilizado',
        DetectionReason.onlyCandidate => 'Único reproductor disponible',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = controller.detection;
    final (String title, String subtitle, IconData icon) = switch (d) {
      PlayerDetected(:final candidate, :final reason) => (
          candidate.status.appName,
          [
            reasonText(reason),
            if (candidate.status.title != null)
              '${candidate.status.title}'
                  '${candidate.status.artist != null ? ' — ${candidate.status.artist}' : ''}',
          ].join('\n'),
          Icons.graphic_eq,
        ),
      NeedsChoice(:final candidates) => (
          'Sin destino claro',
          'Elige entre: ${candidates.map((c) => c.status.appName).join(', ')}',
          Icons.help_outline,
        ),
      NoPlayer() => (
          'Ningún reproductor',
          'SmartBuds AI no detecta música activa.',
          Icons.music_off,
        ),
    };
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceBar extends StatelessWidget {
  const _VoiceBar({required this.voice});
  final VoiceEngine voice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final theme = Theme.of(context);
        final on = voice.enabled;
        final status = !on
            ? 'Toca para que SmartBuds te escuche'
            : voice.listening
                ? 'Escuchando… di «Cambia», «Pausa», «Sube» o «Busca» y una canción'
                : 'Preparando el micrófono…';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton.filled(
                  iconSize: 32,
                  tooltip: on ? 'Dejar de escuchar' : 'Escuchar',
                  onPressed: voice.toggle,
                  icon: Icon(on ? Icons.mic : Icons.mic_none),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(status, style: theme.textTheme.bodyMedium),
                      if (voice.lastHeard.isNotEmpty)
                        Text('Oí: «${voice.lastHeard}»',
                            style: theme.textTheme.bodySmall),
                      if (voice.error != null)
                        Text(voice.error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TestControls extends StatefulWidget {
  const _TestControls({required this.controller});
  final DetectedPlayerController controller;

  @override
  State<_TestControls> createState() => _TestControlsState();
}

class _TestControlsState extends State<_TestControls> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    widget.controller.search(_query.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<CommandSource>(
          segments: const [
            ButtonSegment(
                value: CommandSource.voice,
                icon: Icon(Icons.mic),
                label: Text('Como voz')),
            ButtonSegment(
                value: CommandSource.manual,
                icon: Icon(Icons.touch_app),
                label: Text('Manual')),
          ],
          selected: {c.testSource},
          onSelectionChanged: (s) => c.setTestSource(s.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmd(c, MusicCommand.previous, Icons.skip_previous, 'Devuelve'),
            _cmd(c, MusicCommand.pause, Icons.pause, 'Pausa'),
            _cmd(c, MusicCommand.play, Icons.play_arrow, 'Continúa'),
            _cmd(c, MusicCommand.next, Icons.skip_next, 'Cambia'),
            _cmd(c, MusicCommand.volumeDown, Icons.volume_down, 'Baja'),
            _cmd(c, MusicCommand.volumeUp, Icons.volume_up, 'Sube'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Ojalá Ryan Castro',
                  labelText: '«Busca…» (prueba sin voz)',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: c.busy ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('Buscar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cmd(DetectedPlayerController c, MusicCommand m, IconData i, String l) =>
      FilledButton.tonalIcon(
        onPressed: c.busy ? null : () => c.send(m),
        icon: Icon(i),
        label: Text('«$l»'),
      );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});
  final CommandResult result;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (result.outcome) {
      CommandOutcome.verified => (Icons.check_circle, Colors.green),
      CommandOutcome.sentUnverified => (Icons.schedule, Colors.orange),
      CommandOutcome.needsChoice => (Icons.help, Colors.blue),
      CommandOutcome.notAllowed => (Icons.block, Colors.red),
      _ => (Icons.error_outline, Colors.red),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(result.message),
      subtitle: Text(result.outcome.name),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.view, required this.controller});
  final PlayerView view;
  final DetectedPlayerController controller;

  static String levelText(ControlLevel l) => switch (l) {
        ControlLevel.direct => 'Control directo',
        ControlLevel.limited => 'Control limitado',
        ControlLevel.unsupported => 'No compatible',
      };

  static const _labels = {
    MusicCommand.play: 'Reproducir',
    MusicCommand.pause: 'Pausa',
    MusicCommand.togglePlayPause: 'Alternar',
    MusicCommand.next: 'Siguiente',
    MusicCommand.previous: 'Anterior',
    MusicCommand.volumeUp: 'Vol +',
    MusicCommand.volumeDown: 'Vol −',
  };

  @override
  Widget build(BuildContext context) {
    final s = view.status;
    final caps = controller.testSource == CommandSource.voice
        ? view.voiceCaps
        : view.manualCaps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.appName,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(label: Text(s.state.name)),
              ],
            ),
            Text(s.packageName, style: Theme.of(context).textTheme.bodySmall),
            if (s.title != null) Text('${s.title} — ${s.artist ?? ''}'),
            const SizedBox(height: 8),
            Text(
              '${levelText(caps.level)} '
              '(${controller.testSource == CommandSource.voice ? 'voz' : 'manual'})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (caps.reason != null) Text(caps.reason!),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cmd in MusicCommand.values)
                  FilterChip(
                    label: Text(_labels[cmd]!),
                    selected: caps.allows(cmd),
                    onSelected: caps.allows(cmd) &&
                            !cmd.isVolume &&
                            !controller.busy
                        ? (_) => controller.sendTo(view.candidate, cmd)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityLog extends StatelessWidget {
  const _CapabilityLog({required this.controller});
  final DetectedPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final log = controller.capabilities.log;
    return ExpansionTile(
      title: Text('Registro de capacidades (${log.length})'),
      children: [
        for (final r in log.take(30))
          ListTile(
            dense: true,
            title: Text('${r.player.appName} · ${r.source.name}'),
            subtitle: Text(
              '${r.at.toIso8601String().substring(11, 19)} — '
              'declarado: ${r.declared.supported.map((c) => c.name).join(', ')}\n'
              'efectivo: ${r.effective.supported.map((c) => c.name).join(', ')}'
              '${r.effective.reason != null ? '\n${r.effective.reason}' : ''}',
            ),
          ),
      ],
    );
  }
}
