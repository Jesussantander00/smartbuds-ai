import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import '../jarvis/jarvis_core.dart';
import '../modules/modules.dart';

/// Centro de control y transparencia: qué escucha SmartBuds, qué hizo, qué
/// permisos usa y para qué, qué datos guarda y con quién se conecta.
class ControlCenterScreen extends StatelessWidget {
  const ControlCenterScreen({super.key, required this.assistant, this.onOpenPermissions});
  final Assistant assistant;
  final Future<void> Function()? onOpenPermissions;

  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _title(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(text, style: theme.textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = assistant.settings;
    final voice = assistant.voice;
    final profile = assistant.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Centro de control')),
      body: ListenableBuilder(
        listenable: Listenable.merge([assistant, if (settings != null) settings, if (voice != null) voice]),
        builder: (context, _) {
          final on = (String id) => settings?.moduleOn(id) ?? true;
          final connections = <(IconData, String, String, bool)>[
            (Icons.cloud_rounded, 'Tu cuenta (Supabase)', 'Gustos, amigos, dispositivos y copia', settings?.signedIn ?? false),
            (Icons.travel_explore_rounded, 'Deezer', 'Artistas parecidos y datos de artistas (sin tu identidad)', true),
            (Icons.menu_book_rounded, 'Wikipedia', 'Resumen de artistas («cuéntame de…»)', on('knowledge')),
            (Icons.smart_display_rounded, 'YouTube (Google)', 'Buscar canciones', assistant.finder != null),
            (Icons.wb_sunny_rounded, 'Open-Meteo e ipwho.is', 'Clima con tu ubicación aproximada (sin GPS)', assistant.weather != null),
            (Icons.lightbulb_rounded, 'Tu hogar inteligente', '${settings?.homeHooks.length ?? 0} avisos configurados',
                on('smarthome') && (settings?.homeHooks.isNotEmpty ?? false)),
            (Icons.bug_report_rounded, 'Reportes de errores', 'Solo el tipo de error, anónimo', settings?.errorReports ?? false),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ------------------------------------------------------- Ahora
              NeonCard(
                child: Row(
                  children: [
                    if (voice != null) JarvisCore(voice: voice, size: 84) else const AppIcon(Icons.mic_off_rounded, colors: AppColors.devices, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            voice == null || !voice.enabled ? 'Micrófono apagado' : 'Escucha continua encendida',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text('Las órdenes se reconocen en el teléfono; el audio no se guarda ni se envía.'),
                          if (settings?.privateMode ?? false)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('Modo privado activo: no se guarda lo que escuchas.'),
                            ),
                          if (voice != null && voice.enabled)
                            TextButton.icon(
                              onPressed: voice.stop,
                              icon: const Icon(Icons.mic_off_rounded),
                              label: const Text('Apagar el micrófono'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ------------------------------------------- Actividad
              _title(theme, 'Lo que hizo el asistente'),
              Card(
                child: assistant.actionLog.isEmpty
                    ? const ListTile(title: Text('Nada todavía en esta sesión.'))
                    : Column(
                        children: [
                          for (final e in assistant.actionLog.take(25))
                            ListTile(dense: true, leading: Text(_time(e.at)), title: Text(e.what)),
                        ],
                      ),
              ),
              if (voice != null && voice.history.isNotEmpty) ...[
                _title(theme, 'Lo que te escuchó'),
                Card(
                  child: Column(
                    children: [
                      for (final h in voice.history.take(15))
                        ListTile(
                          dense: true,
                          leading: Text(_time(h.at)),
                          title: Text('«${h.heard}»'),
                          subtitle: Text(h.action),
                        ),
                    ],
                  ),
                ),
              ],
              Text('El registro vive solo en la memoria del teléfono y se borra al cerrar la app.',
                  style: theme.textTheme.bodySmall),
              // ------------------------------------------- Permisos
              _title(theme, 'Permisos y para qué'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.mic_rounded),
                      title: Text('Micrófono'),
                      subtitle: Text('Escuchar tus órdenes («Cambia», «Pausa»…). También «Solo mi voz» y el visualizador.'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.notifications_rounded),
                      title: Text('Acceso a notificaciones (Android)'),
                      subtitle: Text('Ver qué suena en tus apps de música y controlarlas. No lee tus mensajes.'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.bluetooth_rounded),
                      title: Text('Bluetooth'),
                      subtitle: Text('Saber cuándo conectas tus audífonos o el carro.'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text('Ajustes de audio'),
                      subtitle: Text('Volumen, transiciones, ecualizador y visualizador.'),
                    ),
                    if (onOpenPermissions != null)
                      TextButton.icon(
                        onPressed: onOpenPermissions,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Revisar permisos en el teléfono'),
                      ),
                  ],
                ),
              ),
              // ------------------------------------------- Datos
              _title(theme, 'Datos guardados'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone_android_rounded),
                      title: const Text('En este teléfono'),
                      subtitle: Text(
                        '${profile.tracks.length} canciones · ${profile.history.length} eventos de escucha · '
                        '${settings?.automations.length ?? 0} automatizaciones · ${settings?.curatedLists.length ?? 0} listas · '
                        '${settings?.connectionLog.length ?? 0} conexiones de audífonos',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: const Text('En tu cuenta'),
                      subtitle: Text(settings?.signedIn ?? false
                          ? 'Gustos sincronizados, amigos, dispositivos y copia de seguridad (solo tú los ves).'
                          : 'No has entrado con una cuenta: nada se guarda en la nube.'),
                    ),
                  ],
                ),
              ),
              // ------------------------------------------- Conexiones
              _title(theme, 'Conexiones externas'),
              Card(
                child: Column(
                  children: [
                    for (final (icon, name, what, active) in connections)
                      ListTile(
                        leading: Icon(icon),
                        title: Text(name),
                        subtitle: Text(what),
                        trailing: Text(active ? 'Activa' : 'Sin usar',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: active ? const Color(0xFF1FA889) : theme.colorScheme.outline,
                            )),
                      ),
                  ],
                ),
              ),
              Text(
                'Extensiones activas: ${smartBudsModules.where((m) => on(m.id)).map((m) => m.name).join(', ')}.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
