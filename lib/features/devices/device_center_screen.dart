import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import 'device_hub.dart';

/// Centro multidispositivo: este teléfono, tus otros dispositivos con la misma
/// cuenta, el modo carro y el reloj, en un solo panel.
class DeviceCenterScreen extends StatefulWidget {
  const DeviceCenterScreen({super.key, required this.assistant, this.hub});
  final Assistant assistant;
  final DeviceHub? hub;

  @override
  State<DeviceCenterScreen> createState() => _DeviceCenterScreenState();
}

class _DeviceCenterScreenState extends State<DeviceCenterScreen> {
  Assistant get a => widget.assistant;

  @override
  void initState() {
    super.initState();
    final hub = widget.hub;
    if (hub != null) {
      hub.publish(a.active);
      hub.refresh();
    }
  }

  static String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  static IconData _icon(String platform) => switch (platform) {
        'ios' => Icons.phone_iphone_rounded,
        'android' => Icons.phone_android_rounded,
        'web' => Icons.laptop_rounded,
        _ => Icons.devices_other_rounded,
      };

  Future<void> _rename(DeviceHub hub) async {
    final ctrl = TextEditingController(text: hub.myName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre de este teléfono'),
        content: TextField(controller: ctrl, maxLength: 40, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (name == null) return;
    a.settings?.setDeviceName(name);
    await hub.publish(a.active);
    await hub.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = a.settings;
    final hub = widget.hub;
    if (settings == null) return const Scaffold(body: SizedBox.shrink());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro multidispositivo'),
        actions: [
          if (hub != null) IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: hub.refresh),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, a, if (hub != null) hub]),
        builder: (context, _) {
          final now = DateTime.now();
          final s = a.active;
          // Bluetooth conocidos: los que tienen volumen guardado o se conectaron.
          final known = <String>{
            ...settings.carDevices,
            if (settings.lastHeadphone != null) settings.lastHeadphone!,
            ...settings.headphoneVolumes.keys,
            for (final e in settings.connectionLog)
              if (e.name != null) e.name!,
          }.toList()
            ..sort();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ------------------------------------------------ Este teléfono
              NeonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIcon(_icon(DeviceHub.platform), colors: AppColors.devices, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hub?.myName ?? 'Este teléfono', style: theme.textTheme.titleMedium),
                              Text('Este dispositivo', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (hub != null)
                          IconButton(
                            tooltip: 'Cambiar nombre',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _rename(hub),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _line(Icons.music_note_rounded,
                        s?.title == null ? 'Nada sonando' : '${s!.title} · ${s.artist ?? ''} (${s.appName})'),
                    _line(Icons.headphones_rounded, a.headphoneName ?? 'Sin audífonos Bluetooth'),
                    if (hub != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar en mis otros dispositivos'),
                        subtitle: const Text('Solo tu cuenta lo ve. En modo privado no se comparte.'),
                        value: settings.shareDevices,
                        onChanged: (v) async {
                          settings.update(shareDevices: v);
                          if (v) {
                            await hub.publish(a.active);
                          } else {
                            await hub.forgetThisDevice();
                          }
                        },
                      ),
                  ],
                ),
              ),
              // ------------------------------------- Tus otros dispositivos
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text('Tus otros dispositivos', style: theme.textTheme.titleMedium),
              ),
              if (hub == null || !settings.signedIn)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('Entra con tu cuenta'),
                    subtitle: Text('Abre SmartBuds con la misma cuenta en otro teléfono y aparecerá aquí.'),
                  ),
                )
              else ...[
                if (hub.loading && hub.devices.isEmpty) const LinearProgressIndicator(),
                if (hub.error != null)
                  Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(hub.error!))),
                if (!hub.loading && hub.others.isEmpty && hub.error == null)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.devices_other_rounded),
                      title: Text('Aún no hay otros dispositivos'),
                      subtitle: Text('Abre SmartBuds con tu cuenta en otro teléfono o tablet.'),
                    ),
                  ),
                for (final d in hub.others)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_icon(d.platform)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(d.name, style: theme.textTheme.titleSmall)),
                              Icon(Icons.circle, size: 10, color: d.onlineAt(now) ? const Color(0xFF1FA889) : Colors.grey),
                              const SizedBox(width: 6),
                              Text(_ago(d.updatedAt, now), style: theme.textTheme.bodySmall),
                              PopupMenuButton<String>(
                                onSelected: (_) => hub.remove(d),
                                itemBuilder: (_) => const [PopupMenuItem(value: 'x', child: Text('Quitar de la lista'))],
                              ),
                            ],
                          ),
                          Text(
                            d.title == null
                                ? 'Nada sonando'
                                : '${d.playing ? '▶' : '⏸'} ${d.title}${d.artist == null ? '' : ' · ${d.artist}'}'
                                    '${d.app == null ? '' : ' (${d.app})'}',
                          ),
                          if (d.title != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('Continuar aquí'),
                                onPressed: () => a.handleSearch(
                                    SearchRequest([d.title, if (d.artist != null) d.artist].join(' '))),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(
                    'Ves qué suena en cada uno y puedes seguir la canción aquí. Controlar la música de otro '
                    'teléfono a distancia no es posible: el sistema solo deja controlar la del propio teléfono.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
              // ------------------------------------------------- Modo carro
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text('Modo carro', style: theme.textTheme.titleMedium),
              ),
              NeonCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.directions_car_rounded),
                      label: const Text('Abrir modo carro'),
                      onPressed: () => a.setCarMode(true),
                    ),
                    const SizedBox(height: 6),
                    const Text('Botones grandes y voz siempre activa. También: «modo carro».'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Abrir solo al conectar el carro'),
                      value: settings.carAutoOpen,
                      onChanged: (v) => settings.update(carAutoOpen: v),
                    ),
                    if (known.isEmpty)
                      const Text('Conecta el Bluetooth del carro una vez para poder marcarlo.')
                    else ...[
                      const Text('¿Cuál es tu carro?'),
                      for (final n in known)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(n),
                          value: settings.carDevices.contains(n),
                          onChanged: (v) => settings.setCarDevice(n, v ?? false),
                        ),
                    ],
                    Text(
                      'No es Android Auto ni CarPlay: esas pantallas solo aceptan apps que reproducen su propia '
                      'música. Mira la pantalla solo con el carro detenido.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              // ------------------------------------------------------- Reloj
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text('Reloj', style: theme.textTheme.titleMedium),
              ),
              NeonCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppIcon(Icons.watch_rounded, colors: AppColors.stats, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Platform.isIOS
                            ? 'En Apple Watch usa «Ahora suena» para pausar, cambiar y subir el volumen de lo que '
                                'SmartBuds puso. Una app propia para el reloj aún no existe.'
                            : 'En relojes Wear OS, los controles de música del reloj manejan lo que SmartBuds puso '
                                '(pausa, siguiente, volumen). En el teléfono, la notificación de SmartBuds ahora '
                                'trae «Me gusta». Una app propia para el reloj aún no existe.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
