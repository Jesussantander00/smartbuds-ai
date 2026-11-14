import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/ui/futuristic.dart';
import 'eq_controller.dart';
import 'sound_profiles.dart';

/// Ecualizador inteligente: perfiles por audífono y por tipo de música, bandas
/// manuales y la verdad sobre si el teléfono lo aplicó.
class SmartEqCard extends StatefulWidget {
  const SmartEqCard({super.key, required this.eq});
  final EqController eq;

  @override
  State<SmartEqCard> createState() => _SmartEqCardState();
}

class _SmartEqCardState extends State<SmartEqCard> {
  EqController get eq => widget.eq;
  String _selected = 'flat';

  static const _moods = ['entrenar', 'fiesta', 'concentrarme', 'tranquila', 'dormir'];

  @override
  void initState() {
    super.initState();
    if (eq.available == null) eq.probe();
    final device = eq.assistant.headphoneName;
    _selected = (device == null ? null : eq.settings.eqByDevice[device]) ?? 'flat';
  }

  static String _hz(int hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = eq.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([eq, settings]),
      builder: (context, _) {
        final device = eq.assistant.headphoneName;
        final levels = eq.levelsFor(_selected);
        final unsupported = Platform.isIOS || eq.available == false;
        return NeonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const AppIcon(Icons.tune_rounded, colors: AppColors.home, size: 40),
                title: const Text('Ecualizador inteligente'),
                subtitle: Text(eq.activePreset == null
                    ? 'Perfiles por audífono y por tipo de música.'
                    : 'Ahora: ${eq.activePreset == 'custom' ? 'Manual' : presetById(eq.activePreset).name}'
                        '${eq.reason == null ? '' : ' (por ${eq.reason})'}'),
                value: settings.eqEnabled,
                onChanged: (v) => settings.update(eqEnabled: v),
              ),
              if (eq.applied == true)
                const _Status(ok: true, text: 'El teléfono lo aplicó.')
              else if (eq.applied == false || unsupported)
                _Status(
                  ok: false,
                  text: Platform.isIOS
                      ? 'iPhone no deja ecualizar otras apps: copia estos valores en Ajustes → Música → Ecualizador.'
                      : 'Este teléfono no deja que SmartBuds ecualice la salida general. Usa estos valores en el '
                          'ecualizador del teléfono (abajo).',
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in soundPresets)
                    ChoiceChip(label: Text(p.name), selected: _selected == p.id, onSelected: (_) => setState(() => _selected = p.id)),
                  ChoiceChip(label: const Text('Manual'), selected: _selected == 'custom', onSelected: (_) => setState(() => _selected = 'custom')),
                ],
              ),
              const SizedBox(height: 4),
              Text(_selected == 'custom' ? 'Mueve las bandas a tu gusto.' : presetById(_selected).hint,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: Row(
                  children: [
                    for (var b = 0; b < 5; b++)
                      Expanded(
                        child: Column(
                          children: [
                            Text('${levels[b] > 0 ? '+' : ''}${levels[b].round()} dB', style: theme.textTheme.labelSmall),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  value: levels[b].clamp(-12.0, 12.0),
                                  min: -12,
                                  max: 12,
                                  divisions: 24,
                                  onChanged: (v) {
                                    final next = [...levels]..[b] = v;
                                    settings.setEqCustom(next);
                                    setState(() => _selected = 'custom');
                                  },
                                ),
                              ),
                            ),
                            Text('${_hz(SoundPreset.freqs[b])}Hz', style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: unsupported ? null : () => eq.apply(_selected, because: 'tú lo elegiste'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Probar ahora'),
                  ),
                  if (device != null)
                    OutlinedButton.icon(
                      onPressed: () => settings.setEqForDevice(device, _selected),
                      icon: const Icon(Icons.headphones_rounded),
                      label: Text(settings.eqByDevice[device] == _selected ? 'Guardado para $device' : 'Guardar para $device'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Por tipo de música', style: theme.textTheme.titleSmall),
              Text('Cuando suena ese ambiente, gana sobre el perfil del audífono.', style: theme.textTheme.bodySmall),
              for (final m in _moods)
                Row(
                  children: [
                    Expanded(child: Text(m)),
                    DropdownButton<String?>(
                      value: settings.eqByMood[m],
                      hint: Text('Sugerido: ${presetById(recommendedPresetFor(m)).name}'),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sin perfil')),
                        for (final p in soundPresets) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        const DropdownMenuItem<String?>(value: 'custom', child: Text('Manual')),
                      ],
                      onChanged: (v) => settings.setEqForMood(m, v),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 18, color: ok ? const Color(0xFF1FA889) : const Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );
}
