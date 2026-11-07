import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../assistant/assistant.dart';
import '../assistant/assistant_screen.dart';
import '../devices/detected_player_controller.dart';
import '../devices/detected_player_screen.dart';
import '../home/home_screen.dart';
import '../music_profile/music_profile.dart';
import '../music_profile/my_music_screen.dart';
import '../music_profile/supabase_sync.dart';

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
    this.onOpenNotificationAccess,
    this.platformNote,
  });

  final DetectedPlayerController controller;
  final Assistant assistant;
  final MusicProfile profile;
  final AppSettings settings;
  final VoiceEngine? voice;
  final SupabaseSync? sync;
  final Future<void> Function()? onOpenNotificationAccess;
  final String? platformNote;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: widget.controller, assistant: widget.assistant, voice: widget.voice),
      AssistantScreen(settings: widget.settings, voice: widget.voice),
      MyMusicScreen(profile: widget.profile, assistant: widget.assistant, sync: widget.sync),
      // Diagnóstico de reproductores y capacidades (sin micrófono propio).
      DetectedPlayerScreen(
        controller: widget.controller,
        onOpenPermissions: widget.onOpenNotificationAccess,
        platformNote: widget.platformNote,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Asistente'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Mi música'),
          NavigationDestination(icon: Icon(Icons.headphones_outlined), selectedIcon: Icon(Icons.headphones), label: 'Dispositivos'),
        ],
      ),
    );
  }
}
