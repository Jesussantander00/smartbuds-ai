import '../../connectors/connector_interface.dart';
import '../models.dart';

/// Regla de política para una aplicación concreta. Se aplica encima de
/// lo que el conector declara: una política solo puede quitar acciones,
/// nunca añadir acciones que el reproductor no ofrece.
class PlatformPolicy {
  const PlatformPolicy({
    required this.packageName,
    required this.label,
    required this.blockedSources,
    required this.reason,
  });

  final String packageName;
  final String label;
  final Set<CommandSource> blockedSources;
  final String reason;
}

/// Políticas por defecto, alineadas con las decisiones del documento
/// de arquitectura. Revisar cada vez que cambien los términos de un servicio.
const defaultPolicies = <PlatformPolicy>[
  PlatformPolicy(
    packageName: 'com.spotify.music',
    label: 'Spotify por voz',
    blockedSources: {CommandSource.voice},
    reason: 'No habilitado: restricción de las políticas de desarrollo de '
        'Spotify sobre control por voz.',
  ),
];

/// Una línea del registro de capacidades.
class CapabilityRecord {
  const CapabilityRecord({
    required this.at,
    required this.player,
    required this.source,
    required this.declared,
    required this.effective,
  });

  final DateTime at;
  final PlayerStatus player;
  final CommandSource source;
  final Capabilities declared;
  final Capabilities effective;
}

/// Decide qué acciones están permitidas para un reproductor y un origen.
class CapabilityManager {
  CapabilityManager({List<PlatformPolicy> policies = defaultPolicies})
      : _policies = {for (final p in policies) p.packageName: p};

  final Map<String, PlatformPolicy> _policies;
  final List<CapabilityRecord> _log = [];

  /// Registro de capacidades (las más recientes primero), máx. 100 entradas.
  List<CapabilityRecord> get log => List.unmodifiable(_log.reversed);

  PlatformPolicy? policyFor(String packageName) => _policies[packageName];

  Future<Capabilities> evaluate(
    MusicConnector connector,
    PlayerStatus status,
    CommandSource source,
  ) async {
    final declared = await connector.getCapabilities();
    final effective = applyPolicy(declared, status.packageName, source);
    _log.add(CapabilityRecord(
      at: DateTime.now(),
      player: status,
      source: source,
      declared: declared,
      effective: effective,
    ));
    if (_log.length > 100) _log.removeAt(0);
    return effective;
  }

  /// Puro y testeable: combina lo declarado con la política.
  Capabilities applyPolicy(
    Capabilities declared,
    String packageName,
    CommandSource source,
  ) {
    final policy = _policies[packageName];
    if (policy == null || !policy.blockedSources.contains(source)) {
      return declared;
    }
    // El volumen es del sistema y no pasa por el reproductor.
    final remaining = declared.supported.where((c) => c.isVolume).toSet();
    return Capabilities(
      supported: remaining,
      level: declared.level == ControlLevel.unsupported
          ? ControlLevel.unsupported
          : ControlLevel.limited,
      reason: policy.reason,
    );
  }
}
