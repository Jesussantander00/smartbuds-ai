import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';
import 'modules.dart';

/// Extensiones: enciende o apaga módulos de SmartBuds, y lo que viene en Premium.
class ExtensionsScreen extends StatelessWidget {
  const ExtensionsScreen({super.key, required this.settings});
  final AppSettings settings;

  static Widget _support(String label, Support s, ThemeData theme) {
    final (icon, color, text) = switch (s) {
      Support.full => (Icons.check_circle_rounded, const Color(0xFF1FA889), label),
      Support.partial => (Icons.adjust_rounded, const Color(0xFFF59E0B), '$label (parcial)'),
      Support.none => (Icons.cancel_rounded, theme.colorScheme.outline, '$label no'),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Extensiones')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            NeonCard(
              child: Text(
                'Elige qué partes de SmartBuds usar. El núcleo (reproducción, voz y cerebro musical) '
                'siempre está. Las extensiones vienen dentro de la app y llegan con las actualizaciones: '
                'Google Play y App Store no permiten descargar código nuevo después de instalar.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            for (final m in smartBudsModules)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        secondary: AppIcon(m.icon, colors: m.colors, size: 40),
                        title: Row(
                          children: [
                            Flexible(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1FA889).withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Gratis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        subtitle: Text(m.description),
                        value: settings.moduleOn(m.id),
                        onChanged: (v) => settings.setModule(m.id, v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _support('Android', m.android, theme),
                            _support('iPhone', m.iphone, theme),
                            for (final p in m.permissions)
                              Chip(
                                avatar: const Icon(Icons.lock_outline_rounded, size: 14),
                                label: Text(p),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text('Depende de: ${m.dependsOn}', style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            NeonCard(
              tint: const Color(0xFFF59E0B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppIcon(Icons.workspace_premium_rounded, colors: AppColors.radio, size: 40),
                      const SizedBox(width: 12),
                      Expanded(child: Text('SmartBuds Premium · próximamente', style: theme.textTheme.titleMedium)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hoy todo es gratis, y las funciones básicas lo seguirán siendo siempre: reproducir, '
                    'controlar por voz, aprender tus gustos y tus estadísticas. Premium sería para extras '
                    'como temas exclusivos o informes más profundos.',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Para cobrar una suscripción hacen falta cuentas de desarrollador en Google Play y '
                    'App Store; mientras tanto no hay pagos en la app.',
                    style: theme.textTheme.bodySmall,
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
