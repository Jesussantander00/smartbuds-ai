import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import '../assistant/assistant.dart';
import 'smart_eq_card.dart';

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
                  // ------------------------------- Ecualizador inteligente
                  if (a.eq != null) SmartEqCard(eq: a.eq!),
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
                              const Text('Real = lo informa el sistema · Estimado = calculado por SmartBuds',
                                  style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 4),
                              _row('Sale por', [i['type'], i['name']].whereType<String>().join(' · ')),
                              _row('Frecuencia del sistema', _rate(i['nativeSampleRate'])),
                              if ((i['sampleRates'] as List?)?.isNotEmpty ?? false)
                                _row('El dispositivo admite',
                                    (i['sampleRates'] as List).map(_rate).toSet().join(', ')),
                              if ((i['channelCounts'] as List?)?.isNotEmpty ?? false)
                                _row('Canales', (i['channelCounts'] as List).toSet().join(', ')),
                              _latency(i),
                              _row('Volumen', '${i['volumePercent'] ?? '—'} %'),
                              _row('Códec Bluetooth', 'No disponible', estimate: null),
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
                  // ------------------------------- Calidad por plataforma
                  const _PlatformQualityCard(),
                  // ---------------------------------------------- Transiciones
                  NeonCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const AppIcon(Icons.swap_horiz_rounded, colors: AppColors.assistant, size: 40),
                      title: const Text('Transiciones suaves'),
                      subtitle: Text(Platform.isIOS
                          ? 'No disponible en iPhone (no deja cambiar el volumen de otras apps).'
                          : 'Baja el volumen poco a poco al final de cada canción y al cambiarla, y lo vuelve a subir '
                              'cuando empieza la siguiente. No es un crossfade real.'),
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
    if (ms is int && ms > 0) return _row('Latencia de salida', '$ms ms', estimate: true);
    final frames = int.tryParse('${i['framesPerBuffer']}');
    final rate = int.tryParse('${i['nativeSampleRate']}');
    if (frames == null || rate == null || rate == 0) return const SizedBox.shrink();
    return _row('Búfer del sistema', '${(frames / rate * 1000).toStringAsFixed(1)} ms', estimate: true);
  }

  /// [estimate]: false = dato real del sistema, true = estimado, null = no disponible.
  Widget _row(String label, String value, {bool? estimate = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(width: 6),
            _Tag(estimate),
          ],
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.estimate);
  final bool? estimate;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (estimate) {
      false => ('Real', const Color(0xFF1FA889)),
      true => ('Estimado', const Color(0xFFF59E0B)),
      null => ('No disponible', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// Calidad máxima que publica cada plataforma (puede cambiar por plan y país).
class _PlatformQualityCard extends StatelessWidget {
  const _PlatformQualityCard();

  static const rows = [
    ('Apple Music', 'AAC 256 kbps · sin pérdida ALAC hasta 24 bits/192 kHz'),
    ('Spotify', 'Premium: sin pérdida FLAC hasta 24 bits/44,1 kHz (desde 2025)'),
    ('Amazon Music', 'Sin pérdida FLAC hasta 24 bits/192 kHz'),
    ('Tidal', 'Sin pérdida FLAC hasta 24 bits/192 kHz'),
    ('Deezer', 'Sin pérdida FLAC 16 bits/44,1 kHz'),
    ('YouTube Music', 'AAC hasta 256 kbps · sin opción sin pérdida'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIcon(Icons.high_quality_rounded, colors: AppColors.night, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text('Calidad de cada plataforma', style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          for (final (name, q) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Text(q)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Dato publicado por cada plataforma (noviembre de 2026); depende de tu plan, tu país y la calidad '
            'elegida en su app. Por Bluetooth el sonido se vuelve a comprimir (SBC, AAC, LDAC…): con audífonos '
            'inalámbricos el límite suele ser el códec, no la app.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
