import 'package:flutter/material.dart';

import '../../core/voice_engine/voice_engine.dart';
import '../devices/detected_player_controller.dart';

/// Bienvenida: pide los permisos paso a paso y hace una prueba de voz.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.controller,
    required this.onFinished,
    this.voice,
    this.onOpenNotificationAccess,
    this.onRequestMusicAccess,
    this.hasMusicAccess,
  });

  final DetectedPlayerController controller;
  final VoiceEngine? voice;
  final Future<void> Function()? onOpenNotificationAccess;

  /// Solo iPhone: pedir y consultar el permiso de Apple Music. Si están, el
  /// primer paso habla de Apple Music en vez del acceso a notificaciones.
  final Future<bool> Function()? onRequestMusicAccess;
  final Future<bool> Function()? hasMusicAccess;
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  bool _micGranted = false;
  bool _musicGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de Ajustes, revisar de nuevo los permisos.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    await widget.controller.refresh();
    final mic = await widget.voice?.hasPermission() ?? true;
    final music = await widget.hasMusicAccess?.call() ?? false;
    if (mounted) {
      setState(() {
        _micGranted = mic;
        _musicGranted = music;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voice = widget.voice;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.controller, if (voice != null) voice]),
          builder: (context, _) {
            final notificationsOk = widget.controller.missingPermissions.isEmpty;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.headphones, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Bienvenido a SmartBuds',
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Controla tu música con la voz, sin tocar el teléfono. '
                  'Tres pasos y listo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (widget.onRequestMusicAccess != null)
                  _Step(
                    number: 1,
                    title: 'Conectar Apple Music',
                    body: 'En iPhone, SmartBuds controla la app Música con tu cuenta '
                        '(hace falta suscripción a Apple Music).',
                    done: _musicGranted,
                    action: TextButton(
                      onPressed: () async {
                        final ok = await widget.onRequestMusicAccess!();
                        if (mounted) setState(() => _musicGranted = ok);
                      },
                      child: const Text('Permitir'),
                    ),
                  )
                else
                  _Step(
                    number: 1,
                    title: 'Ver qué música suena',
                    body: 'Activa «SmartBuds AI» en Acceso a notificaciones. '
                        'Así SmartBuds detecta YouTube Music, Apple Music y otras apps.',
                    done: notificationsOk,
                    action: widget.onOpenNotificationAccess == null
                        ? null
                        : TextButton(
                            onPressed: widget.onOpenNotificationAccess,
                            child: const Text('Activar'),
                          ),
                  ),
                _Step(
                  number: 2,
                  title: 'Escucharte',
                  body: 'Permite el micrófono para escuchar tus órdenes '
                      '(también con la pantalla apagada).',
                  done: _micGranted,
                  action: voice == null
                      ? null
                      : TextButton(
                          onPressed: () async {
                            final ok = await voice.requestPermission();
                            if (mounted) setState(() => _micGranted = ok);
                          },
                          child: const Text('Permitir'),
                        ),
                ),
                _Step(
                  number: 3,
                  title: 'Pruébalo',
                  body: voice == null
                      ? 'La voz no está disponible en este dispositivo.'
                      : voice.enabled
                          ? (voice.lastHeard.isEmpty
                              ? 'Pon una canción y di «Cambia».'
                              : 'Oí: «${voice.lastHeard}». ¡Funciona!')
                          : 'Toca el micrófono, pon una canción y di «Cambia».',
                  done: voice?.lastCommand != null,
                  action: voice == null
                      ? null
                      : IconButton.filledTonal(
                          onPressed: voice.toggle,
                          icon: Icon(voice.enabled ? Icons.mic : Icons.mic_none),
                        ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onFinished,
                  child: const Text('Empezar'),
                ),
                TextButton(
                  onPressed: widget.onFinished,
                  child: const Text('Lo configuro después'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.done,
    this.action,
  });

  final int number;
  final String title;
  final String body;
  final bool done;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: done ? Colors.green : theme.colorScheme.secondaryContainer,
          child: done ? const Icon(Icons.check, color: Colors.white) : Text('$number'),
        ),
        title: Text(title),
        subtitle: Text(body),
        trailing: done ? null : action,
        isThreeLine: true,
      ),
    );
  }
}
