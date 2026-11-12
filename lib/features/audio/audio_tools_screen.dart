import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';

/// Herramientas de audio: ecualizador del teléfono, calidad de la salida,
/// transiciones suaves y perfil de sonido por audífono.
///
/// Límite honesto: en Android moderno y en iPhone una app no puede ecualizar
/// ni mezclar el audio de otras apps (Spotify, YouTube Music…). Por eso el
/// ecualizador abre el del teléfono, y las transiciones juegan con el volumen.
class AudioToolsScreen extends StatefulWidget {
  const AudioToolsScreen({super.key, required this.assistant});
  final Assistant assistant;

  @override
  State<AudioToolsScreen> createState() => _AudioToolsScreenState();
}

class _AudioToolsScreenState extends State<AudioToolsScreen> {
  late Future<Map<String, dynamic>?> _info = widget.assistant.media?.audioOutputInfo() ?? Future.value(null);

  Assistant get a => widget.assistant;

  String _rate(dynamic v) {
    final n = int.tryParse('$v');
    if (n == null || n <= 0) return '—';
    return n % 1000 == 0 ? '${n ~/ 1000} kHz' : '${(n / 1000).toStringAsFixed(1)} kHz';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = a.settings;
    final phones = a.headphoneName;
    return Scaffold(
      appBar: AppBar(title: const Text('Herramientas de audio')),
      body: settings == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: settings,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  // ---------------------------------------------- Ecualizador
                  NeonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppIcon(Icons.equalizer_rounded, colors: AppColors.home, size: 40),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Ecualizador', style: theme.textTheme.titleMedium)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Platform.isIOS
                              ? 'iPhone no deja que otras apps cambien el sonido de Apple Music. '
                                  'Usa Ajustes → Apps → Música → Ecualizador.'
                              : 'Graves, medios y agudos se ajustan en el ecualizador de tu teléfono '
                                  '(Samsung, Dolby, Xiaomi…), que cambia el sonido de todas las apps.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (!Platform.isIOS) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () async {
                              final ok = await a.media?.openSystemEqualizer() ?? false;
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('Este teléfono no trae ecualizador. '
                                        'Revisa la app de tu música o la de tus audífonos.')));
                              }
                            },
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Abrir el ecualizador del teléfono'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // ---------------------------------------- Calidad del audio
                  NeonCard(
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future: _info,
                      builder: (context, snap) {
                        final i = snap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const AppIcon(Icons.graphic_eq_rounded, colors: AppColors.stats, size: 40),
                                const SizedBox(width: 12),
                                Expanded(child: Text('Calidad de la salida', style: theme.textTheme.titleMedium)),
                                IconButton(
                                  tooltip: 'Actualizar',
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () => setState(() =>
                                      _info = a.media?.audioOutputInfo() ?? Future.value(null)),
                                ),
                              ],
                            ),
                            if (snap.connectionState != ConnectionState.done)
                              const LinearProgressIndicator()
                            else if (i == null || i['available'] != true)
                              const Text('El teléfono no informó datos de la salida de audio.')
                            else ...[
                              _row('Sale por', [i['type'], i['name']].whereType<String>().join(' · ')),
                              _row('Frecuencia del sistema', _rate(i['nativeSampleRate'])),
                              if ((i['sampleRates'] as List?)?.isNotEmpty ?? false)
                                _row('El dispositivo admite',
                                    (i['sampleRates'] as List).map(_rate).toSet().join(', ')),
                              if ((i['channelCounts'] as List?)?.isNotEmpty ?? false)
                                _row('Canales', (i['channelCounts'] as List).toSet().join(', ')),
                              _latency(i),
                              _row('Volumen', '${i['volumePercent'] ?? '—'} %'),
                              const SizedBox(height: 6),
                              Text(
                                'El códec Bluetooth (AAC, LDAC…) y la calidad del archivo los maneja la app '
                                'de música y el sistema; no se los comparten a otras apps.',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  // ---------------------------------------------- Transiciones
                  NeonCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const AppIcon(Icons.swap_horiz_rounded, colors: AppColors.assistant, size: 40),
                      title: const Text('Transiciones suaves'),
                      subtitle: Text(Platform.isIOS
                          ? 'No disponible en iPhone (no deja cambiar el volumen de otras apps).'
                          : 'Al cambiar de canción con SmartBuds, baja el volumen poco a poco, cambia y lo vuelve a subir.'),
                      value: settings.smoothTransitions,
                      onChanged: Platform.isIOS ? null : (v) => settings.update(smoothTransitions: v),
                    ),
                  ),
                  // ------------------------------------------ Perfil de sonido
                  NeonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppIcon(Icons.headphones_rounded, colors: AppColors.devices, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(phones == null ? 'Perfil de sonido' : 'Perfil de $phones',
                                  style: theme.textTheme.titleMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (phones == null)
                          const Text('Conecta tus audífonos para guardar su perfil.')
                        else ...[
                          _row('Volumen guardado', '${settings.headphoneVolumes[phones] ?? '—'} %'),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Límite de volumen'),
                            subtitle: const Text('Cuida tus oídos: SmartBuds nunca pasa de aquí con estos audífonos.'),
                            value: settings.volumeCaps[phones] != null,
                            onChanged: Platform.isIOS
                                ? null
                                : (v) => settings.setVolumeCap(phones, v ? 80 : null),
                          ),
                          if (settings.volumeCaps[phones] != null)
                            Slider(
                              value: settings.volumeCaps[phones]!.toDouble(),
                              min: 20,
                              max: 100,
                              divisions: 16,
                              label: '${settings.volumeCaps[phones]} %',
                              onChanged: (v) => settings.setVolumeCap(phones, v.round()),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _latency(Map<String, dynamic> i) {
    final ms = i['outputLatencyMs'];
    if (ms is int && ms > 0) return _row('Latencia de salida', '$ms ms');
    final frames = int.tryParse('${i['framesPerBuffer']}');
    final rate = int.tryParse('${i['nativeSampleRate']}');
    if (frames == null || rate == null || rate == 0) return const SizedBox.shrink();
    return _row('Búfer del sistema', '${(frames / rate * 1000).toStringAsFixed(1)} ms');
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
