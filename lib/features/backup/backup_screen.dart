import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/futuristic.dart';
import 'backup_service.dart';

/// Copia de seguridad: en la nube (con tu cuenta) o como texto.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.backup, required this.deviceName, this.share});
  final BackupService backup;
  final String deviceName;

  /// Compartir texto con otras apps (si el teléfono lo permite).
  final Future<bool> Function(String text)? share;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupService get b => widget.backup;

  @override
  void initState() {
    super.initState();
    b.refreshCloud();
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return '${t.day}/${t.month}/${t.year}';
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _confirmRestore(Future<({int songs, int automations})?> Function() restore) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Restaurar la copia?'),
        content: const Text('Tus ajustes y automatizaciones se reemplazan por los de la copia. '
            'Tus gustos se unen con los de este teléfono (no se borra nada).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await restore();
    if (!mounted) return;
    _snack(r == null
        ? (b.error ?? 'Esa copia no es válida.')
        : 'Listo: ${r.songs} canciones y ${r.automations} automatizaciones restauradas.');
  }

  Future<void> _importText() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pegar copia'),
        content: TextField(controller: ctrl, maxLines: 5, decoration: const InputDecoration(hintText: 'Pega aquí la copia')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Siguiente')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;
    await _confirmRestore(() => b.restore(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = b.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Copia de seguridad')),
      body: ListenableBuilder(
        listenable: Listenable.merge([b, settings]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            NeonCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIcon(Icons.cloud_done_rounded, colors: AppColors.assistant, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Guarda tus ajustes, perfiles, automatizaciones, audífonos y gustos para recuperarlos '
                      'al cambiar de teléfono. No incluye tu sesión ni tu huella de voz.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('En la nube', style: theme.textTheme.titleMedium),
            ),
            if (!b.cloudAvailable)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Entra con tu cuenta'),
                  subtitle: Text('Así tu copia queda guardada y la recuperas en otro teléfono.'),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    if (b.busy) const LinearProgressIndicator(),
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(b.cloud == null ? 'Aún no hay copia' : 'Última copia: ${_when(b.cloud!.at)}'),
                      subtitle: b.cloud == null
                          ? null
                          : Text('${b.cloud!.device ?? 'Otro dispositivo'} · ${b.cloud!.songs} canciones · '
                              '${b.cloud!.automations} automatizaciones'),
                    ),
                    if (b.error != null)
                      ListTile(
                        leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                        title: Text(b.error!),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: b.busy
                                  ? null
                                  : () async {
                                      final ok = await b.saveToCloud(device: widget.deviceName);
                                      if (mounted) _snack(ok ? 'Copia guardada.' : (b.error ?? 'No se pudo guardar.'));
                                    },
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Guardar ahora'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: b.busy || b.cloud == null ? null : () => _confirmRestore(b.restoreFromCloud),
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Restaurar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Copia automática'),
                      subtitle: const Text('Una vez al día al abrir SmartBuds.'),
                      value: settings.autoBackup,
                      onChanged: (v) => settings.update(autoBackup: v),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('Como texto', style: theme.textTheme.titleMedium),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.ios_share_rounded),
                    title: const Text('Exportar copia'),
                    subtitle: const Text('Guárdala en tus notas o envíatela.'),
                    onTap: () async {
                      final text = b.exportText(device: widget.deviceName);
                      final shared = await widget.share?.call(text) ?? false;
                      if (!shared) {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (mounted) _snack('Copia guardada en el portapapeles.');
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Importar copia'),
                    subtitle: const Text('Pega el texto que exportaste (también las copias viejas de gustos).'),
                    onTap: _importText,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
