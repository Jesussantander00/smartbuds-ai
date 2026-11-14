import 'dart:async';

import '../../core/models.dart';
import '../../core/settings/app_settings.dart';

/// Lo que necesita para bajar y subir el volumen (Android).
abstract class VolumeFader {
  Future<int?> volumePercent();
  Future<void> fadeVolume(int to, {int ms});
}

/// Transiciones inteligentes: cuando una canción está por terminar baja el
/// volumen poco a poco y, cuando empieza la siguiente, lo vuelve a subir.
///
/// Límite honesto: no es un crossfade real (dos canciones mezcladas): eso solo
/// lo puede hacer la app que reproduce. Necesita que la app informe la duración
/// y la posición, y que el teléfono deje cambiar el volumen (Android).
class TransitionWatcher {
  TransitionWatcher({
    required this.settings,
    required this.fader,
    DateTime Function()? clock,
    this.window = const Duration(seconds: 4),
    this.fadeOut = const Duration(milliseconds: 3000),
  }) : _clock = clock ?? DateTime.now;

  final AppSettings settings;
  final VolumeFader fader;
  final DateTime Function() _clock;
  final Duration window, fadeOut;

  String? _fadedKey;
  int? _restoreTo;
  DateTime? _fadedAt;
  Timer? _tick;
  PlayerStatus? _last;

  bool get fading => _restoreTo != null;

  /// Tiempo que le falta a la canción, o null si la app no lo informa.
  Duration? remaining(PlayerStatus s) {
    final d = s.durationMs, p = s.positionMs;
    if (d == null || p == null || d <= 0 || !s.isPlaying) return null;
    final since = s.lastActiveAt == null ? 0 : _clock().difference(s.lastActiveAt!).inMilliseconds;
    return Duration(milliseconds: d - (p + since));
  }

  /// Llamar con cada cambio del reproductor (y lo revisa cada segundo mientras suena).
  Future<void> update(PlayerStatus? s) async {
    _last = s;
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(check()));
    await check();
  }

  Future<void> check() async {
    final s = _last;
    // Empezó otra canción (o se pausó, o pasó demasiado): vuelve el volumen.
    if (fading) {
      final stale = _fadedAt != null && _clock().difference(_fadedAt!) > const Duration(seconds: 12);
      if (s == null || s.trackKey != _fadedKey || !s.isPlaying || stale) {
        final to = _restoreTo!;
        _restoreTo = null;
        _fadedAt = null;
        await fader.fadeVolume(to, ms: 1500);
      }
      return;
    }
    if (s == null || !settings.smoothTransitions || s.trackKey == _fadedKey) return;
    final left = remaining(s);
    if (left == null || left > window || left.isNegative) return;
    final before = await fader.volumePercent();
    if (before == null || before < 10) return;
    _fadedKey = s.trackKey;
    _restoreTo = before;
    _fadedAt = _clock();
    await fader.fadeVolume((before * .35).round(), ms: fadeOut.inMilliseconds);
  }

  void dispose() => _tick?.cancel();
}
