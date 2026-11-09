import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
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
                _Appear(
                  index: 0,
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => Neon.gradient.createShader(r),
                        child: const Icon(Icons.headphones, size: 72, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const NeonEqualizer(playing: true, height: 28),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Appear(
                  index: 1,
                  child: Text('Bienvenido a SmartBuds',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                const _Appear(
                  index: 2,
                  child: Text(
                    'Controla tu música con la voz, sin tocar el teléfono. '
                    'Tres pasos y listo.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.onRequestMusicAccess != null)
                  _Step(
                    index: 3,
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
                    index: 3,
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
                  index: 4,
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
                  index: 5,
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
                _Appear(
                  index: 6,
                  child: FilledButton(
                    onPressed: widget.onFinished,
                    child: const Text('Empezar'),
                  ),
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
    required this.index,
    required this.number,
    required this.title,
    required this.body,
    required this.done,
    this.action,
  });

  final int index;
  final int number;
  final String title;
  final String body;
  final bool done;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Appear(
      index: index,
      child: Card(
      child: ListTile(
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
          child: CircleAvatar(
            key: ValueKey(done),
            backgroundColor: done ? Colors.green : theme.colorScheme.secondaryContainer,
            child: done ? const Icon(Icons.check, color: Colors.white) : Text('$number'),
          ),
        ),
        title: Text(title),
        subtitle: Text(body),
        trailing: done ? null : action,
        isThreeLine: true,
      ),
      ),
    );
  }
}

/// Aparece deslizándose desde abajo, uno tras otro según [index].
class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final delay = index * 120;
    final total = 450 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
