import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../connectors/android_media/android_media_connector.dart';
import '../../core/settings/app_settings.dart';
import '../assistant/assistant.dart';
import 'sound_profiles.dart';

/// Ecualizador inteligente: aplica el perfil de tus audífonos o el del tipo de
/// música que suena, y dice la verdad sobre si el teléfono lo aceptó.
class EqController extends ChangeNotifier {
  EqController({required this.assistant, required this.settings, this.media}) {
    assistant.addListener(_onChange);
    settings.addListener(_onChange);
  }

  final Assistant assistant;
  final AppSettings settings;
  final AndroidMediaSource? media;

  /// Bandas reales del teléfono (Hz) y rango (milibelios), si hay ecualizador.
  List<int> bands = const [];
  int minMb = -1500, maxMb = 1500;
  bool? available;

  /// Lo último aplicado y por qué (para mostrarlo).
  String? activePreset;
  String? reason;

  /// true = el teléfono lo aplicó; false = lo rechazó; null = aún no se intentó.
  bool? applied;

  String? _lastKey;

  Future<void> probe() async {
    final info = await media?.eqInfo();
    available = info?['available'] == true;
    if (available!) {
      bands = [for (final b in (info!['bands'] as List)) (b as num).toInt()];
      minMb = (info['min'] as num).toInt();
      maxMb = (info['max'] as num).toInt();
    }
    notifyListeners();
  }

  /// Qué perfil toca ahora: el del tipo de música (si lo elegiste) o el de los audífonos.
  ({String preset, String reason})? choose() {
    final mood = assistant.brain.ambience()?.mood ?? assistant.profile.currentMood;
    if (mood != null && settings.eqByMood[mood] != null) {
      return (preset: settings.eqByMood[mood]!, reason: 'música «$mood»');
    }
    final device = assistant.headphoneName;
    if (device != null && settings.eqByDevice[device] != null) {
      return (preset: settings.eqByDevice[device]!, reason: device);
    }
    return null;
  }

  List<double> levelsFor(String preset) => preset == 'custom' ? settings.eqCustom : presetById(preset).db;

  void _onChange() {
    if (!settings.eqEnabled) {
      if (_lastKey != null) {
        _lastKey = null;
        activePreset = null;
        applied = null;
        unawaited(media?.eqRelease() ?? Future.value());
        notifyListeners();
      }
      return;
    }
    final c = choose();
    final key = c == null ? 'none' : '${c.preset}|${levelsFor(c.preset).join(',')}';
    if (key == _lastKey) return;
    _lastKey = key;
    if (c == null) return;
    unawaited(apply(c.preset, because: c.reason));
  }

  /// Aplica un perfil y comprueba si el teléfono lo aceptó.
  Future<bool> apply(String preset, {String? because}) async {
    if (available == null) await probe();
    activePreset = preset;
    reason = because;
    if (available != true || media == null) {
      applied = false;
      notifyListeners();
      return false;
    }
    applied = await media!.eqApply(mapToDevice(levelsFor(preset), bands, minMb, maxMb));
    notifyListeners();
    return applied!;
  }

  @override
  void dispose() {
    assistant.removeListener(_onChange);
    settings.removeListener(_onChange);
    super.dispose();
  }
}
