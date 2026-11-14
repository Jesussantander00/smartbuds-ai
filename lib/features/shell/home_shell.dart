import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../account/supabase_auth.dart';
import '../assistant/assistant.dart';
import '../assistant/assistant_screen.dart';
import '../devices/detected_player_controller.dart';
import '../devices/detected_player_screen.dart';
import '../devices/device_hub.dart';
import '../backup/backup_service.dart';
import '../car/car_mode_screen.dart';
import '../home/home_screen.dart';
import '../music_profile/music_profile.dart';
import '../music_profile/my_music_screen.dart';
import '../music_profile/supabase_sync.dart';
import 'glass_sidebar.dart';
import '../modules/extensions_screen.dart';
import '../modules/modules.dart';
import '../../core/ui/futuristic.dart';
import '../privacy/privacy_screen.dart';
import '../social/social_screen.dart';
import '../social/social_service.dart';
import '../social/listen_party.dart';

/// Navegación principal: Inicio · Asistente · Mi música · Dispositivos.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.assistant,
    required this.profile,
    required this.settings,
    this.voice,
    this.sync,
    this.auth,
    this.onHeadphoneTapsChanged,
    this.onOpenNotificationAccess,
    this.platformNote,
  });

  final DetectedPlayerController controller;
  final Assistant assistant;
  final MusicProfile profile;
  final AppSettings settings;
  final VoiceEngine? voice;
  final SupabaseSync? sync;
  final SupabaseAuth? auth;
  final ValueChanged<bool>? onHeadphoneTapsChanged;
  final Future<void> Function()? onOpenNotificationAccess;
  final String? platformNote;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _open = false;
  SocialService? _social;
  ListenParty? _party;
  DeviceHub? _hub;
  late final BackupService _backup;
  Route<void>? _carRoute;

  @override
  void initState() {
    super.initState();
    final auth = widget.auth;
    if (auth != null) {
      _social = SocialService(url: auth.url, anonKey: auth.anonKey, auth: auth, settings: widget.settings);
      _social!.refresh();
      _party = ListenParty(social: _social!, assistant: widget.assistant, controller: widget.controller);
      if (widget.settings.signedIn && widget.settings.moduleOn('social')) _party!.resume();
      _hub = DeviceHub(url: auth.url, anonKey: auth.anonKey, auth: auth, settings: widget.settings);
    }
    _backup = BackupService(
      settings: widget.settings,
      profile: widget.profile,
      auth: auth,
      url: auth?.url,
      anonKey: auth?.anonKey,
    );
    widget.assistant.addListener(_onAssistant);
    widget.controller.addListener(_onAssistant);
    WidgetsBinding.instance.addPostFrameCallback((_) => _backupCheck());
  }

  String get _deviceName => _hub?.myName ?? widget.settings.deviceName ?? 'Este teléfono';

  /// Copia diaria y, si este teléfono está vacío y hay copia en la nube, ofrecerla.
  Future<void> _backupCheck() async {
    if (!widget.settings.signedIn) return;
    if (await _backup.shouldOfferRestore()) {
      if (!mounted) return;
      final c = _backup.cloud!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('Tienes una copia de ${c.device ?? 'otro teléfono'} con ${c.songs} canciones.'),
        action: SnackBarAction(
          label: 'Restaurar',
          onPressed: () async {
            final r = await _backup.restoreFromCloud();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(r == null ? (_backup.error ?? 'No se pudo restaurar.') : 'Listo: tu SmartBuds volvió.')));
          },
        ),
      ));
      return;
    }
    await _backup.autoBackup(device: _deviceName);
  }

  /// Publica lo que suena para tus otros dispositivos y abre el modo carro
  /// cuando el asistente lo pide (voz o Bluetooth del carro).
  void _onAssistant() {
    final a = widget.assistant;
    _hub?.publish(a.active);
    // Fuera del ciclo de dibujo: el aviso puede llegar mientras se construye.
    Future.microtask(_syncCarMode);
  }

  void _syncCarMode() {
    if (!mounted) return;
    final a = widget.assistant;
    if (a.carMode && _carRoute == null) {
      final route = MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CarModeScreen(assistant: a, voice: widget.voice),
      );
      _carRoute = route;
      Navigator.of(context).push(route).whenComplete(() {
        if (_carRoute == route) _carRoute = null;
        a.setCarMode(false);
      });
    } else if (!a.carMode && _carRoute != null) {
      final route = _carRoute!;
      _carRoute = null;
      if (route.isActive) Navigator.of(context).removeRoute(route);
    }
  }

  @override
  void dispose() {
    widget.assistant.removeListener(_onAssistant);
    widget.controller.removeListener(_onAssistant);
    _hub?.dispose();
    _backup.dispose();
    _party?.dispose();
    _social?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: widget.controller, assistant: widget.assistant, voice: widget.voice),
      AssistantScreen(
        settings: widget.settings,
        voice: widget.voice,
        onHeadphoneTapsChanged: widget.onHeadphoneTapsChanged,
        assistant: widget.assistant,
      ),
      MyMusicScreen(
        profile: widget.profile,
        assistant: widget.assistant,
        sync: widget.sync,
        auth: widget.auth,
        backup: _backup,
        deviceName: _deviceName,
      ),
      ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => widget.settings.moduleOn('social')
            ? SocialScreen(assistant: widget.assistant, social: _social, party: _party)
            : _ModuleOff(settings: widget.settings, id: 'social'),
      ),
      // Diagnóstico de reproductores y capacidades (sin micrófono propio).
      DetectedPlayerScreen(
        controller: widget.controller,
        onOpenPermissions: widget.onOpenNotificationAccess,
        platformNote: widget.platformNote,
        assistant: widget.assistant,
        hub: _hub,
      ),
      PrivacyScreen(
        assistant: widget.assistant,
        controller: widget.controller,
        onOpenPermissions: widget.onOpenNotificationAccess,
      ),
    ];
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 900; // en computadora/tablet queda abierta al lado
    final open = _open || wide;
    final railSpace = (wide ? GlassSidebar.expandedWidth : GlassSidebar.collapsedWidth) + 20;
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: railSpace),
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: IndexedStack(index: _tab, children: pages),
            ),
          ),
          // Al abrir la barra en el teléfono, oscurece suavemente el resto.
          if (_open && !wide)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _open = false),
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: ColoredBox(color: Colors.black.withValues(alpha: .18)),
                ),
              ),
            ),
          Positioned(
            left: 10,
            top: media.padding.top + 10,
            bottom: media.padding.bottom + 10,
            child: GlassSidebar(
              expanded: open,
              onToggle: wide ? () {} : () => setState(() => _open = !_open),
              selected: _tab,
              onSelect: (i) => setState(() {
                _tab = i;
                _open = false;
              }),
              assistant: widget.assistant,
              controller: widget.controller,
              settings: widget.settings,
              voice: widget.voice,
              social: _social,
            ),
          ),
        ],
      ),
    );
  }
}

/// Página de un módulo apagado: qué es y cómo volver a encenderlo.
class _ModuleOff extends StatelessWidget {
  const _ModuleOff({required this.settings, required this.id});
  final AppSettings settings;
  final String id;

  @override
  Widget build(BuildContext context) {
    final m = moduleById(id);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(m.icon, colors: m.colors, size: 64),
            const SizedBox(height: 16),
            Text('${m.name} está apagado', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(m.description, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => settings.setModule(id, true), child: const Text('Encender')),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ExtensionsScreen(settings: settings)),
              ),
              child: const Text('Ver extensiones'),
            ),
          ],
        ),
      ),
    );
  }
}
