import 'dart:async';

import '../connectors/connector_interface.dart';
import 'player_detector/active_player_detector.dart';

/// Reúne todas las fuentes de reproductores (Android Media Session,
/// Apple Music, reproductor propio…) y entrega candidatos con su estado.
class ConnectorManager {
  ConnectorManager(this.sources);

  final List<PlayerSource> sources;

  /// Permisos que faltan, por fuente. Vacío si todo está concedido.
  Future<Map<String, String>> missingPermissions() async {
    final result = <String, String>{};
    for (final s in sources) {
      final missing = await s.missingPermission();
      if (missing != null) result[s.sourceId] = missing;
    }
    return result;
  }

  /// Descubre reproductores y consulta su estado. Un conector que falla
  /// se omite en lugar de romper la detección de los demás.
  Future<List<PlayerCandidate>> candidates() async {
    final out = <PlayerCandidate>[];
    for (final source in sources) {
      if (await source.missingPermission() != null) continue;
      final List<MusicConnector> connectors;
      try {
        connectors = await source.discover();
      } catch (_) {
        continue;
      }
      for (final c in connectors) {
        try {
          if (!await c.isAvailable()) continue;
          out.add(PlayerCandidate(c, await c.getStatus()));
        } catch (_) {
          // Sesión cerrada entre discover() y getStatus().
        }
      }
    }
    return out;
  }

  /// Une los avisos de cambio de todas las fuentes.
  Stream<void> get changes {
    if (sources.isEmpty) return const Stream.empty();
    if (sources.length == 1) return sources.single.changes;
    final controller = StreamController<void>.broadcast();
    final subs = <StreamSubscription<void>>[];
    controller.onListen = () {
      for (final s in sources) {
        subs.add(s.changes.listen(controller.add));
      }
    };
    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      subs.clear();
    };
    return controller.stream;
  }
}
