import 'dart:math';

import 'package:flutter/foundation.dart';

import '../player_detector/active_player_detector.dart';
import '../storage/json_store.dart';

/// Ajustes de la app, guardados en el teléfono. También recuerda el último
/// reproductor usado entre sesiones (implementa [LastUsedStore]).
class AppSettings extends ChangeNotifier implements LastUsedStore {
  AppSettings({JsonStore? store}) : _store = store ?? MemoryJsonStore();

  final JsonStore _store;

  bool onboardingDone = false;

  /// SmartBuds responde con voz («Reproduciendo…»).
  bool voiceFeedback = true;

  /// Pausar la escucha al quitar los audífonos y reanudarla al conectarlos.
  bool followHeadphones = true;

  /// «Solo mi voz»: huella de voz entrenada, si está activo y qué tan estricto.
  List<double>? voiceprint;
  bool onlyMyVoice = false;
  double voiceThreshold = 0.5;

  /// Identificador anónimo del dispositivo (para sincronizar el perfil).
  String deviceId = '';

  String? _lastUsedPlayerId;

  @override
  String? get lastUsedPlayerId => _lastUsedPlayerId;

  @override
  set lastUsedPlayerId(String? id) {
    if (id == _lastUsedPlayerId) return;
    _lastUsedPlayerId = id;
    _persist();
  }

  Future<void> load() async {
    final d = await _store.load() ?? const {};
    onboardingDone = d['onboardingDone'] == true;
    voiceFeedback = d['voiceFeedback'] != false;
    followHeadphones = d['followHeadphones'] != false;
    _lastUsedPlayerId = d['lastUsedPlayerId'] as String?;
    voiceprint = (d['voiceprint'] as List?)?.map((e) => (e as num).toDouble()).toList();
    onlyMyVoice = d['onlyMyVoice'] == true;
    voiceThreshold = (d['voiceThreshold'] as num?)?.toDouble() ?? 0.5;
    deviceId = (d['deviceId'] as String?) ?? _newId();
    if (d['deviceId'] == null) await _persist();
    notifyListeners();
  }

  void update({
    bool? onboardingDone,
    bool? voiceFeedback,
    bool? followHeadphones,
    List<double>? voiceprint,
    bool clearVoiceprint = false,
    bool? onlyMyVoice,
    double? voiceThreshold,
  }) {
    if (voiceprint != null) this.voiceprint = voiceprint;
    if (clearVoiceprint) this.voiceprint = null;
    if (onlyMyVoice != null) this.onlyMyVoice = onlyMyVoice;
    if (voiceThreshold != null) this.voiceThreshold = voiceThreshold;
    if (onboardingDone != null) this.onboardingDone = onboardingDone;
    if (voiceFeedback != null) this.voiceFeedback = voiceFeedback;
    if (followHeadphones != null) this.followHeadphones = followHeadphones;
    _persist();
    notifyListeners();
  }

  Future<void> _persist() => _store.save({
        'onboardingDone': onboardingDone,
        'voiceFeedback': voiceFeedback,
        'followHeadphones': followHeadphones,
        'lastUsedPlayerId': _lastUsedPlayerId,
        'deviceId': deviceId,
        'voiceprint': voiceprint,
        'onlyMyVoice': onlyMyVoice,
        'voiceThreshold': voiceThreshold,
      });

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
