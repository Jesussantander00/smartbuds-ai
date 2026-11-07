import '../../connectors/connector_interface.dart';
import '../models.dart';

/// Un reproductor descubierto, con su estado ya consultado.
class PlayerCandidate {
  const PlayerCandidate(this.connector, this.status);
  final MusicConnector connector;
  final PlayerStatus status;
}

/// Por qué se eligió un reproductor (se muestra en pantalla y en el registro).
enum DetectionReason { playing, recentlyActive, lastUsed, onlyCandidate }

sealed class DetectionResult {
  const DetectionResult();
}

class PlayerDetected extends DetectionResult {
  const PlayerDetected(this.candidate, this.reason);
  final PlayerCandidate candidate;
  final DetectionReason reason;
}

class NeedsChoice extends DetectionResult {
  const NeedsChoice(this.candidates);
  final List<PlayerCandidate> candidates;
}

class NoPlayer extends DetectionResult {
  const NoPlayer();
}

/// Recuerda el último reproductor que el usuario controló.
abstract class LastUsedStore {
  String? get lastUsedPlayerId;
  set lastUsedPlayerId(String? id);
}

class InMemoryLastUsedStore implements LastUsedStore {
  @override
  String? lastUsedPlayerId;
}

/// Aplica la lógica de prioridades de la arquitectura:
///   1. Reproductor que está reproduciendo audio.
///   2. Reproductor que acaba de estar activo.
///   3. Último reproductor utilizado.
///   4. Si no hay destino claro, pedir una elección.
class ActivePlayerDetector {
  ActivePlayerDetector({
    required this.lastUsed,
    this.recentWindow = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LastUsedStore lastUsed;

  /// Cuánto tiempo cuenta un reproductor pausado como «recién activo».
  final Duration recentWindow;
  final DateTime Function() _clock;

  /// [candidates] debe venir en el orden de prioridad del sistema
  /// (en Android, el orden de `getActiveSessions`), que se usa para desempatar.
  DetectionResult detect(List<PlayerCandidate> candidates) {
    if (candidates.isEmpty) return const NoPlayer();

    // 1. Reproduciendo ahora. Si hay varios, el más reciente.
    final playing = candidates.where((c) => c.status.isPlaying).toList();
    if (playing.isNotEmpty) {
      return PlayerDetected(_mostRecent(playing), DetectionReason.playing);
    }

    // 2. Activo hace poco (pausado dentro de la ventana).
    final now = _clock();
    final recent = candidates.where((c) {
      final t = c.status.lastActiveAt;
      return t != null && now.difference(t) <= recentWindow;
    }).toList();
    if (recent.length == 1) {
      return PlayerDetected(recent.single, DetectionReason.recentlyActive);
    }
    if (recent.length > 1) {
      // Varios activos hace poco: solo hay destino claro si uno es
      // claramente el más reciente (más de 10 s de diferencia).
      final sorted = _sortedByRecency(recent);
      final a = sorted[0].status.lastActiveAt!;
      final b = sorted[1].status.lastActiveAt!;
      if (a.difference(b).inSeconds > 10) {
        return PlayerDetected(sorted.first, DetectionReason.recentlyActive);
      }
    }

    // 3. Último reproductor utilizado, si sigue presente.
    final lastId = lastUsed.lastUsedPlayerId;
    if (lastId != null) {
      for (final c in candidates) {
        if (c.status.playerId == lastId) {
          return PlayerDetected(c, DetectionReason.lastUsed);
        }
      }
    }

    // Un único reproductor disponible: no hace falta preguntar.
    if (candidates.length == 1) {
      return PlayerDetected(candidates.single, DetectionReason.onlyCandidate);
    }

    // 4. Sin destino claro.
    return NeedsChoice(List.unmodifiable(recent.isNotEmpty ? recent : candidates));
  }

  PlayerCandidate _mostRecent(List<PlayerCandidate> list) =>
      _sortedByRecency(list).first;

  /// Más reciente primero; sin fecha al final. Los empates conservan el
  /// orden del sistema (List.sort de Dart no es estable, por eso el índice).
  static List<PlayerCandidate> _sortedByRecency(List<PlayerCandidate> list) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((x, y) {
      final a = x.$2.status.lastActiveAt;
      final b = y.$2.status.lastActiveAt;
      final int cmp;
      if (a == null && b == null) {
        cmp = 0;
      } else if (a == null) {
        cmp = 1;
      } else if (b == null) {
        cmp = -1;
      } else {
        cmp = b.compareTo(a);
      }
      return cmp != 0 ? cmp : x.$1.compareTo(y.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}
