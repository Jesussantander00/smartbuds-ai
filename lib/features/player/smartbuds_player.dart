import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import 'catalog.dart';

/// Estado que informa un motor de reproducción.
class EngineState {
  const EngineState(this.state, {this.positionMs, this.durationMs, this.error, this.ended = false});
  final PlaybackState state;
  final int? positionMs;
  final int? durationMs;
  final String? error;

  /// La canción terminó.
  final bool ended;
}

/// Motor que hace sonar una canción (audio por dirección o YouTube incrustado).
abstract class PlaybackEngine {
  /// Se llama cada vez que cambia el estado o avanza la posición.
  void Function(EngineState s)? onState;
  Future<void> load(InAppTrack track);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(int positionMs);

  /// Volumen del reproductor de SmartBuds (0–100), no el del teléfono.
  Future<void> setVolume(int percent);
}

/// Audio por dirección con el reproductor nativo (Android: MediaPlayer;
/// iPhone: AVPlayer). Sigue sonando con la pantalla apagada.
class NativeAudioEngine extends PlaybackEngine {
  NativeAudioEngine({MethodChannel? method, EventChannel? events})
      : _method = method ?? const MethodChannel('smartbuds/player'),
        _events = events ?? const EventChannel('smartbuds/player/events');
  final MethodChannel _method;
  final EventChannel _events;
  StreamSubscription<dynamic>? _sub;

  void _attach() {
    _sub ??= _events.receiveBroadcastStream().listen((e) {
      if (e is! Map) return;
      if (e['type'] == 'error') {
        onState?.call(EngineState(PlaybackState.stopped, error: '${e['message']}'));
        return;
      }
      final st = switch (e['state']) {
        'playing' => PlaybackState.playing,
        'paused' => PlaybackState.paused,
        'buffering' => PlaybackState.buffering,
        _ => PlaybackState.stopped,
      };
      onState?.call(EngineState(st,
          positionMs: (e['positionMs'] as num?)?.toInt(),
          durationMs: (e['durationMs'] as num?)?.toInt(),
          ended: e['state'] == 'completed'));
    }, onError: (_) {});
  }

  Future<void> _call(String m, [Map<String, Object?>? args]) async {
    try {
      await _method.invokeMethod(m, args);
    } catch (_) {}
  }

  @override
  Future<void> load(InAppTrack track) async {
    _attach();
    await _call('play', {'url': track.streamUrl, 'title': track.title, 'artist': track.artist});
  }

  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> resume() => _call('resume');
  @override
  Future<void> stop() => _call('stop');
  @override
  Future<void> seek(int positionMs) => _call('seek', {'positionMs': positionMs});
  @override
  Future<void> setVolume(int percent) => _call('setVolume', {'percent': percent});
}

/// Reproductor integrado de SmartBuds: cola de resultados, estado, posición y
/// controles. No finge: si la canción suena en otra app, esto no se usa.
class SmartBudsPlayer extends ChangeNotifier {
  SmartBudsPlayer({
    required this.catalog,
    required PlaybackEngine Function(InAppSource source) engineFor,
    DateTime Function()? clock,
  })  : _engineFor = engineFor,
        _clock = clock ?? DateTime.now;

  final MusicCatalog catalog;
  final PlaybackEngine Function(InAppSource source) _engineFor;
  final DateTime Function() _clock;
  final Map<InAppSource, PlaybackEngine> _engines = {};

  InAppTrack? current;
  PlaybackState state = PlaybackState.stopped;
  int positionMs = 0;
  int? durationMs;
  String? error;
  int volume = 100;
  DateTime? _lastActiveAt;

  /// Últimos resultados de búsqueda (para elegir otra canción).
  List<InAppTrack> results = const [];
  String? lastQuery;

  /// Canciones que ya sonaron (para «anterior»).
  final List<InAppTrack> history = [];

  /// Avisa cuando una canción terminó sola.
  VoidCallback? onEnded;

  /// «Siguiente» desde la pantalla: el asistente decide (cola de SmartBuds
  /// primero, luego el siguiente resultado).
  Future<void> Function()? onNextRequested;

  /// Panel de resultados abierto y video minimizado (UI del reproductor).
  bool panelOpen = false;
  bool minimized = false;
  bool searching = false;

  void togglePanel() {
    panelOpen = !panelOpen;
    notifyListeners();
  }

  /// Minimizar el video de YouTube lo pausa (no se reproduce oculto).
  Future<void> toggleMinimized() async {
    minimized = !minimized;
    if (minimized && current?.source == InAppSource.youtube && isPlaying) await pause();
    notifyListeners();
  }

  bool get hasTrack => current != null;
  bool get isPlaying => state == PlaybackState.playing || state == PlaybackState.buffering;

  /// El reproductor integrado manda (suena, o se pausó hace menos de 30 min).
  bool get isActive {
    if (current == null) return false;
    if (isPlaying) return true;
    final at = _lastActiveAt;
    return state == PlaybackState.paused && at != null && _clock().difference(at) < const Duration(minutes: 30);
  }

  PlaybackEngine _engine(InAppSource s) => _engines.putIfAbsent(s, () {
        final e = _engineFor(s);
        e.onState = (st) => _onEngine(s, st);
        return e;
      });

  /// Motor de YouTube (la pantalla necesita mostrar su video).
  PlaybackEngine? engineIfCreated(InAppSource s) => _engines[s];

  int _youtubeRetries = 0;

  void _onEngine(InAppSource from, EngineState s) {
    if (current?.source != from) return; // respuesta de un motor que ya no suena
    state = s.state;
    if (s.positionMs != null) positionMs = s.positionMs!;
    if (s.durationMs != null && s.durationMs! > 0) durationMs = s.durationMs;
    if (s.error != null) {
      error = s.error;
      // Video que no se puede ver fuera de YouTube: prueba el siguiente resultado.
      if (from == InAppSource.youtube && _youtubeRetries < 3) {
        _youtubeRetries++;
        unawaited(nextResult());
        return;
      }
    }
    _lastActiveAt = _clock();
    notifyListeners();
    if (s.ended) {
      state = PlaybackState.stopped;
      notifyListeners();
      onEnded?.call();
    }
  }

  /// Busca y deja los resultados (sin reproducir).
  Future<List<InAppTrack>> search(String query) async {
    lastQuery = query;
    searching = true;
    notifyListeners();
    try {
      results = await catalog.search(query);
    } finally {
      searching = false;
      notifyListeners();
    }
    return results;
  }

  /// Busca y pone la mejor opción. Devuelve la canción, o null si ninguna
  /// fuente integrada la tiene.
  Future<InAppTrack?> playQuery(String query) async {
    _youtubeRetries = 0;
    final list = await search(query);
    final pick = MusicCatalog.best(list, query);
    if (pick == null) return null;
    await play(pick);
    return pick;
  }

  Future<void> play(InAppTrack track) async {
    final prev = current;
    if (prev != null && prev.source != track.source) await _engines[prev.source]?.stop();
    if (prev != null && prev.id != track.id) {
      history.add(prev);
      if (history.length > 50) history.removeAt(0);
    }
    current = track;
    if (track.source == InAppSource.youtube) minimized = false; // el video debe verse
    error = null;
    positionMs = 0;
    durationMs = track.durationMs;
    state = PlaybackState.buffering;
    _lastActiveAt = _clock();
    notifyListeners();
    final e = _engine(track.source);
    await e.load(track);
    await e.setVolume(volume);
  }

  Future<void> pause() async {
    final c = current;
    if (c == null) return;
    await _engine(c.source).pause();
    state = PlaybackState.paused;
    _lastActiveAt = _clock();
    notifyListeners();
  }

  Future<void> resume() async {
    final c = current;
    if (c == null) return;
    if (c.source == InAppSource.youtube) minimized = false; // nunca suena oculto
    await _engine(c.source).resume();
    state = PlaybackState.playing;
    _lastActiveAt = _clock();
    notifyListeners();
  }

  Future<void> toggle() => isPlaying ? pause() : resume();

  Future<void> seek(int ms) async {
    final c = current;
    if (c == null) return;
    positionMs = ms;
    await _engine(c.source).seek(ms);
    notifyListeners();
  }

  /// Siguiente resultado de la última búsqueda (la cola de SmartBuds va primero:
  /// la maneja el asistente).
  Future<bool> nextResult() async {
    final c = current;
    if (results.isEmpty) return false;
    final i = c == null ? -1 : results.indexWhere((r) => r.id == c.id);
    final rest = results.skip(i + 1).where((r) => r.source == (c?.source ?? r.source)).toList();
    if (rest.isEmpty) return false;
    await play(rest.first);
    return true;
  }

  /// Anterior: si va avanzada, vuelve al inicio; si no, la canción de antes.
  Future<void> previous() async {
    if (positionMs > 5000 || history.isEmpty) {
      await seek(0);
      return;
    }
    final prev = history.removeLast();
    final c = current;
    await play(prev);
    if (c != null) history.remove(c);
  }

  Future<void> setVolume(int percent) async {
    volume = percent.clamp(0, 100);
    final c = current;
    if (c != null) await _engine(c.source).setVolume(volume);
    notifyListeners();
  }

  Future<void> stop() async {
    final c = current;
    if (c == null) return;
    await _engine(c.source).stop();
    state = PlaybackState.stopped;
    notifyListeners();
  }

  /// Lo que suena, con el mismo formato que los reproductores externos (para
  /// que el perfil, la cola, las repeticiones y Jarvis lo entiendan igual).
  PlayerStatus? get status {
    final c = current;
    if (c == null) return null;
    return PlayerStatus(
      playerId: 'smartbuds',
      packageName: packageName,
      appName: 'SmartBuds',
      state: state == PlaybackState.buffering ? PlaybackState.playing : state,
      title: c.title,
      artist: c.artist,
      positionMs: positionMs,
      durationMs: durationMs,
      lastActiveAt: _lastActiveAt,
    );
  }

  static const packageName = 'ai.smartbuds.inapp';
}
