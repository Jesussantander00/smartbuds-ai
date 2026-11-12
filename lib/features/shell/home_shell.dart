import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../account/supabase_auth.dart';
import '../assistant/assistant.dart';
import '../assistant/assistant_screen.dart';
import '../devices/detected_player_controller.dart';
import '../devices/detected_player_screen.dart';
import '../home/home_screen.dart';
import '../music_profile/music_profile.dart';
import '../music_profile/my_music_screen.dart';
import '../music_profile/supabase_sync.dart';
import 'glass_sidebar.dart';
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

  @override
  void initState() {
    super.initState();
    final auth = widget.auth;
    if (auth != null) {
      _social = SocialService(url: auth.url, anonKey: auth.anonKey, auth: auth, settings: widget.settings);
      _social!.refresh();
      _party = ListenParty(social: _social!, assistant: widget.assistant, controller: widget.controller);
      if (widget.settings.signedIn) _party!.resume();
    }
  }

  @override
  void dispose() {
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
      ),
      SocialScreen(assistant: widget.assistant, social: _social, party: _party),
      // Diagnóstico de reproductores y capacidades (sin micrófono propio).
      DetectedPlayerScreen(
        controller: widget.controller,
        onOpenPermissions: widget.onOpenNotificationAccess,
        platformNote: widget.platformNote,
        assistant: widget.assistant,
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
