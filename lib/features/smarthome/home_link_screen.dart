import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import 'home_link.dart';

/// Hogar inteligente: tus avisos (webhooks) para luces y ambiente.
class HomeLinkScreen extends StatelessWidget {
  const HomeLinkScreen({super.key, required this.link});
  final HomeLink link;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    var event = 'manual';
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Nuevo aviso'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Fiesta')),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(labelText: 'Dirección (webhook)', hintText: 'https://…'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: event,
                  decoration: const InputDecoration(labelText: 'Cuándo'),
                  items: [
                    for (final e in HomeLink.events.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => set(() => event = v ?? 'manual'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final problem = HomeLink.validate(name.text, url.text);
                if (problem != null) {
                  set(() => error = problem);
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      link.settings.setHomeHooks([
        ...link.settings.homeHooks,
        {'name': name.text.trim(), 'url': url.text.trim(), 'event': event},
      ]);
    }
    name.dispose();
    url.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = link.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Hogar inteligente')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar aviso'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, link]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            NeonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      AppIcon(Icons.lightbulb_rounded, colors: AppColors.radio, size: 40),
                      SizedBox(width: 12),
                      Expanded(child: Text('Luces y ambiente con tu música')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SmartBuds avisa a un servicio tuyo (Home Assistant, IFTTT, Node-RED…) y ese servicio hace '
                    'lo que programaste: luces de fiesta, tono cálido para dormir… Envía solo la canción, el artista '
                    'y el ambiente, nunca en modo privado. Di «escena Fiesta» o úsalo en una automatización.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (settings.homeHooks.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Aún no hay avisos'),
                  subtitle: Text('Ejemplos de dirección:\n'
                      'Home Assistant: https://TU-CASA/api/webhook/ID\n'
                      'IFTTT: https://maker.ifttt.com/trigger/EVENTO/json/with/key/CLAVE'),
                  isThreeLine: true,
                ),
              ),
            for (final (i, h) in settings.homeHooks.indexed)
              Card(
                child: ListTile(
                  leading: Icon(switch (h['event']) {
                    'track' => Icons.music_note_rounded,
                    'mood' => Icons.waves_rounded,
                    _ => Icons.wb_twilight_rounded,
                  }),
                  title: Text(h['name'] ?? ''),
                  subtitle: Text('${HomeLink.events[h['event']] ?? ''}\n'
                      '${Uri.tryParse(h['url'] ?? '')?.host ?? ''}'
                      '${link.lastResult[h['name']] == null ? '' : ' · ${link.lastResult[h['name']]}'}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Probar',
                        icon: const Icon(Icons.send_rounded),
                        onPressed: () => link.test(h),
                      ),
                      IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => settings.setHomeHooks([...settings.homeHooks]..removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'La dirección es como una llave: no la compartas. Se guarda solo en este teléfono (no va en la copia '
              'de seguridad). SmartBuds no controla bombillos directamente: Hue, Google Home y Alexa exigen registrar '
              'la app en sus servicios.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
