import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/ui/futuristic.dart';

/// Estadísticas de unos audífonos sacadas del historial de conexiones.
class HeadphoneReport {
  HeadphoneReport(this.name);
  final String name;
  int connections = 0;
  int disconnections = 0; // reales (no cuenta cambiar a otros audífonos)
  int dropsWeek = 0;
  final List<Duration> sessions = [];
  DateTime? lastSeen;

  Duration? get averageSession => sessions.isEmpty
      ? null
      : Duration(seconds: sessions.fold<int>(0, (a, d) => a + d.inSeconds) ~/ sessions.length);

  /// Sesiones de menos de 2 minutos: señal de cortes.
  int get shortSessions => sessions.where((d) => d < const Duration(minutes: 2)).length;

  /// Qué hacer, según lo que pasó (reglas simples y explicadas).
  List<String> get advice {
    final out = <String>[];
    if (dropsWeek >= 5 || shortSessions >= 3) {
      out.add('Se cortan seguido: acerca el teléfono (sin el cuerpo ni bolsillos de por medio) y aleja otros aparatos Bluetooth o el wifi de 2,4 GHz.');
      out.add('Si sigue: en Ajustes → Bluetooth, «Olvidar» los audífonos y vuelve a emparejarlos.');
      out.add('Cárgalos: con poca batería muchos audífonos pierden la conexión.');
    } else if (dropsWeek >= 2) {
      out.add('Algunos cortes esta semana: revisa la batería y que estén en su estuche cuando no los uses.');
    } else if (connections > 0) {
      out.add('Conexión estable. 👍');
    }
    return out;
  }

  static List<HeadphoneReport> from(AppSettings settings, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final real = settings.realDisconnections().toSet();
    final byName = <String, HeadphoneReport>{};
    // El historial va del más reciente al más antiguo: lo recorremos al revés.
    final log = settings.connectionLog.reversed.toList();
    final openSince = <String, DateTime>{};
    for (final e in log) {
      final name = e.name ?? 'Audífonos sin nombre';
      final r = byName.putIfAbsent(name, () => HeadphoneReport(name));
      r.lastSeen = e.at;
      if (e.connected) {
        r.connections++;
        openSince[name] = e.at;
      } else {
        if (real.contains(e)) {
          r.disconnections++;
          if (today.difference(e.at) < const Duration(days: 7)) r.dropsWeek++;
        }
        final start = openSince.remove(name);
        if (start != null) r.sessions.add(e.at.difference(start));
      }
    }
    final list = byName.values.toList()..sort((a, b) => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)));
    return list;
  }
}

/// Diagnóstico avanzado de audífonos: historial, cortes, duración de cada
/// conexión y recomendaciones.
class HeadphoneDiagnosticsScreen extends StatelessWidget {
  const HeadphoneDiagnosticsScreen({super.key, required this.settings});
  final AppSettings settings;

  static String _dur(Duration d) => d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico de audífonos')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final reports = HeadphoneReport.from(settings);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (reports.isEmpty)
                const Card(child: ListTile(title: Text('Aún no hay conexiones registradas.')))
              else
                for (final r in reports)
                  NeonCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(Icons.headphones_rounded,
                                colors: r.dropsWeek >= 5 ? AppColors.music : AppColors.devices, size: 40),
                            const SizedBox(width: 12),
                            Expanded(child: Text(r.name, style: theme.textTheme.titleMedium)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Chip(label: Text('${r.connections} conexiones')),
                            Chip(label: Text('${r.dropsWeek} cortes esta semana')),
                            if (r.averageSession != null) Chip(label: Text('Promedio ${_dur(r.averageSession!)}')),
                            if (r.lastSeen != null) Chip(label: Text('Última vez ${_when(r.lastSeen!)}')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final a in r.advice)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(a)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Text('Historial', style: theme.textTheme.titleMedium),
              Card(
                child: Column(
                  children: [
                    for (final e in settings.connectionLog.take(40))
                      ListTile(
                        dense: true,
                        leading: Icon(e.connected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                            color: e.connected ? const Color(0xFF1FA889) : theme.colorScheme.error),
                        title: Text('${e.connected ? 'Conectó' : 'Desconectó'} ${e.name ?? ''}'),
                        trailing: Text(_when(e.at), style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Batería y calidad de la señal: Android y iPhone no se las comparten a otras apps (solo la app del '
                'fabricante de tus audífonos las ve). Cambiar de unos audífonos a otros no cuenta como corte.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
