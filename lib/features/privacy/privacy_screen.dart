import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import '../devices/connectivity.dart';
import '../devices/detected_player_controller.dart';
import 'changelog.dart';
import '../modules/extensions_screen.dart';
import '../modules/modules.dart';

/// Privacidad y ayuda: tus datos, permisos, diagnóstico, funciones de prueba,
/// compatibilidad y novedades, en una sola pantalla.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({
    super.key,
    required this.assistant,
    required this.controller,
    this.onOpenPermissions,
  });

  final Assistant assistant;
  final DetectedPlayerController controller;
  final Future<void> Function()? onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final settings = assistant.settings;
    final profile = assistant.profile;
    final theme = Theme.of(context);
    if (settings == null) return const SizedBox.shrink();
    final voice = assistant.voice;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad y ayuda')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, profile, if (voice != null) voice]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 40),
          children: [
            // ------------------------------------------------- Extensiones
            if (assistant.settings != null)
              Card(
                child: ListTile(
                  leading: const AppIcon(Icons.extension_rounded, colors: AppColors.radio, size: 38),
                  title: const Text('Extensiones'),
                  subtitle: Text('${smartBudsModules.where((m) => assistant.settings!.moduleOn(m.id)).length} de '
                      '${smartBudsModules.length} activas · SmartBuds Premium'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ExtensionsScreen(settings: assistant.settings!),
                  )),
                ),
              ),
            // ------------------------------------------------ Modo privado
            NeonCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const AppIcon(Icons.visibility_off_rounded, colors: AppColors.devices, size: 40),
                title: const Text('Modo privado'),
                subtitle: Text(settings.privateMode
                    ? 'Activo: lo que suene no se guarda ni cambia tus recomendaciones.'
                    : 'Escucha sin que SmartBuds aprenda. También: di «modo privado».'),
                value: settings.privateMode,
                onChanged: settings.setPrivateMode,
              ),
            ),
            // ------------------------------------------------- Tus datos
            _Section('Tus datos', Icons.folder_shared_rounded),
            Card(
              child: Column(
                children: [
                  _Info('Canciones que conoce', '${profile.tracks.length}'),
                  _Info('Registros de escucha', '${profile.history.length}'),
                  _Info('Mezclas por ambiente', '${profile.moodTracks.length}'),
                  _Info('Bloqueadas', '${settings.blockedTracks.length + settings.blockedArtists.length}'),
                  _Info('Conexiones de audífonos', '${settings.connectionLog.length}'),
                  _Info('En la nube', settings.signedIn ? 'Sí, con tu cuenta' : 'No (solo en este teléfono)'),
                  const ListTile(
                    dense: true,
                    leading: Icon(Icons.mic_off_rounded),
                    title: Text('Tu voz nunca se guarda ni se envía'),
                    subtitle: Text('Se reconoce en el teléfono y solo queda el texto de la orden, '
                        'que se ve en el historial del Asistente y se borra al cerrar la app.'),
                  ),
                ],
              ),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_delete_outlined),
                    title: const Text('Borrar un periodo'),
                    subtitle: const Text('La última hora, hoy, los últimos 7 días…'),
                    onTap: () => _deleteRange(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.table_view_rounded),
                    title: const Text('Descargar mi historial (tabla)'),
                    subtitle: const Text('Formato CSV para Excel o Google Sheets.'),
                    onTap: () async {
                      final csv = profile.exportCsv();
                      final ok = await assistant.media?.shareText(csv) ?? false;
                      if (!ok) {
                        await Clipboard.setData(ClipboardData(text: csv));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copiado: pégalo en Excel o Google Sheets.')));
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
                    title: Text('Borrar todo lo aprendido', style: TextStyle(color: theme.colorScheme.error)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('¿Borrar todo?'),
                          content: const Text('Se borran tus gustos, historial y mezclas de este teléfono. '
                              'No se puede deshacer.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
                          ],
                        ),
                      );
                      if (ok == true) await profile.clear();
                    },
                  ),
                ],
              ),
            ),
            // ------------------------------------------------- Permisos
            _Section('Permisos por función', Icons.verified_user_rounded),
            Card(
              child: Column(
                children: [
                  if (voice != null)
                    SwitchListTile(
                      secondary: const Icon(Icons.mic_rounded),
                      title: const Text('Micrófono (órdenes de voz)'),
                      value: voice.enabled,
                      onChanged: (_) => voice.toggle(),
                    ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Ver la música de otras apps'),
                    subtitle: const Text('Acceso a notificaciones (lo da Android).'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: onOpenPermissions,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.touch_app_outlined),
                    title: const Text('Toques en los audífonos'),
                    value: settings.headphoneTaps,
                    onChanged: (v) {
                      settings.update(headphoneTaps: v);
                      assistant.media?.setTapGestures(v);
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.place_outlined),
                    title: const Text('Ubicación aproximada (clima)'),
                    subtitle: const Text('Por internet, sin GPS.'),
                    value: settings.weatherSuggestions,
                    onChanged: (v) {
                      settings.update(weatherSuggestions: v);
                      assistant.refreshWeather();
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: const Text('Reportes automáticos de errores'),
                    subtitle: const Text('Anónimos: solo el tipo de error.'),
                    value: settings.errorReports,
                    onChanged: (v) => settings.update(errorReports: v),
                  ),
                ],
              ),
            ),
            // ----------------------------------------------- Diagnóstico
            _Section('Centro de diagnóstico', Icons.monitor_heart_rounded),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.healing_rounded),
                    title: const Text('Revisar todo'),
                    subtitle: const Text('Permisos, reproductor, micrófono, audífonos y conexión.'),
                    onTap: () => showTroubleshooter(
                      context,
                      assistant: assistant,
                      controller: controller,
                      voice: voice,
                      onOpenPermissions: onOpenPermissions,
                    ),
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text('Errores recientes (${assistant.errors?.recent.length ?? 0})'),
                    children: [
                      if ((assistant.errors?.recent ?? const []).isEmpty)
                        const ListTile(dense: true, title: Text('Sin errores. ¡Todo bien!')),
                      for (final e in (assistant.errors?.recent ?? const []).take(10))
                        ListTile(
                          dense: true,
                          title: Text(e.kind),
                          subtitle: Text(e.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(TimeOfDay.fromDateTime(e.at).format(context)),
                        ),
                    ],
                  ),
                  ListTile(
                    leading: const Icon(Icons.send_rounded),
                    title: const Text('Enviar un reporte'),
                    subtitle: const Text('Cuéntanos qué falló; solo se envía si lo confirmas.'),
                    onTap: () => _sendReport(context),
                  ),
                ],
              ),
            ),
            // ------------------------------------------------ Laboratorio
            _Section('Funciones de prueba', Icons.science_rounded),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    dense: true,
                    title: Text('Son nuevas y pueden fallar. Apágalas si algo se comporta raro.'),
                  ),
                  SwitchListTile(
                    title: const Text('Descubrimiento gradual'),
                    value: settings.gradualDiscovery,
                    onChanged: (v) => settings.update(gradualDiscovery: v),
                  ),
                  SwitchListTile(
                    title: const Text('Colores de la carátula'),
                    value: settings.dynamicColors,
                    onChanged: (v) => settings.update(dynamicColors: v),
                  ),
                  SwitchListTile(
                    title: const Text('Sugerencias por clima'),
                    value: settings.weatherSuggestions,
                    onChanged: (v) {
                      settings.update(weatherSuggestions: v);
                      assistant.refreshWeather();
                    },
                  ),
                ],
              ),
            ),
            // --------------------------------------------- Compatibilidad
            _Section('Qué funciona dónde', Icons.devices_rounded),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    headingTextStyle: theme.textTheme.labelLarge,
                    columns: const [
                      DataColumn(label: Text('Función')),
                      DataColumn(label: Text('Web')),
                      DataColumn(label: Text('Android')),
                      DataColumn(label: Text('iPhone')),
                    ],
                    rows: [
                      for (final c in compatibility)
                        DataRow(cells: [
                          DataCell(Text(c.feature, style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(c.web)),
                          DataCell(Text(c.android)),
                          DataCell(Text(c.iphone)),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
            // ------------------------------------------------ Novedades
            _Section('Novedades', Icons.new_releases_rounded),
            for (final c in changelog)
              Card(
                child: ExpansionTile(
                  initiallyExpanded: c.version > settings.lastSeenChangelog || c.version == latestChangelog,
                  onExpansionChanged: (_) => settings.markChangelogSeen(latestChangelog),
                  leading: c.version > settings.lastSeenChangelog
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Neon.pink, borderRadius: BorderRadius.circular(10)),
                          child: const Text('Nuevo',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  title: Text(c.title),
                  children: [
                    for (final i in c.items)
                      ListTile(dense: true, leading: const Icon(Icons.circle, size: 8), title: Text(i)),
                  ],
                ),
              ),
            Center(
              child: TextButton(
                onPressed: () => settings.markChangelogSeen(latestChangelog),
                child: const Text('Marcar novedades como vistas'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRange(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final options = <(String, DateTime)>[
      ('La última hora', now.subtract(const Duration(hours: 1))),
      ('Hoy', today),
      ('Los últimos 7 días', now.subtract(const Duration(days: 7))),
      ('Los últimos 30 días', now.subtract(const Duration(days: 30))),
    ];
    final pick = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('¿Qué periodo quieres borrar?')),
            for (final (label, from) in options)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(label),
                onTap: () => Navigator.pop(c, from),
              ),
          ],
        ),
      ),
    );
    if (pick == null || !context.mounted) return;
    final n = assistant.profile.deleteRange(pick, now.add(const Duration(seconds: 1)));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? 'No había nada en ese periodo.' : 'Listo: borré $n registros.')));
  }

  Future<void> _sendReport(BuildContext context) async {
    final ctrl = TextEditingController();
    final errors = assistant.errors;
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enviar un reporte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '¿Qué pasó? (ej.: no me entiende «busca»)'),
            ),
            const SizedBox(height: 8),
            Text(
              'Se envía: tu texto, el sistema del teléfono y los últimos 3 tipos de error. '
              'Nunca tu voz ni tu historial.',
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Enviar')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    if (errors == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Los reportes no están configurados en esta versión.')));
      return;
    }
    final recent = errors.recent.take(3).map((e) => e.kind).join(', ');
    final ok = await errors.sendUserReport('${text.trim()} | errores: ${recent.isEmpty ? 'ninguno' : recent}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '¡Gracias! Recibimos tu reporte.' : 'No se pudo enviar (¿sin internet?).')));
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.3, color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
