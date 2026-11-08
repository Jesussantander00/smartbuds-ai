import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'command_parser.dart';
import 'speaker_guard.dart';

/// Motor de voz: escucha continua (también con la pantalla apagada) y convierte
/// lo que oye en órdenes. El reconocimiento lo hace el módulo Kotlin
/// `VoiceRecognizer`; la interpretación, [CommandParser].
class VoiceEngine extends ChangeNotifier {
  VoiceEngine({
    required this.onCommand,
    this.onSearch,
    this.onIntent,
    this.parser = const CommandParser(),
    this.repeatCooldown = const Duration(milliseconds: 2500),
    DateTime Function()? clock,
    MethodChannel? method,
    EventChannel? events,
  })  : _clock = clock ?? DateTime.now,
        _method = method ?? const MethodChannel('smartbuds/voice'),
        _events = events ?? const EventChannel('smartbuds/voice/events');

  /// «Cambia», «Pausa», «Sube»…
  final Future<void> Function(MusicCommand command) onCommand;

  /// «Busca <canción>». Null si la búsqueda no está disponible.
  final Future<void> Function(SearchRequest request)? onSearch;

  /// «Me gusta», «No me gusta», «Pon algo que me guste».
  final Future<void> Function(VoiceIntent intent)? onIntent;

  final CommandParser parser;

  /// Tiempo mínimo antes de aceptar otra vez la misma orden.
  final Duration repeatCooldown;
  final DateTime Function() _clock;
  DateTime? _lastCommandAt;
  final MethodChannel _method;
  final EventChannel _events;

  StreamSubscription<dynamic>? _sub;

  /// El usuario activó la escucha.
  bool enabled = false;

  /// El micrófono está abierto en este momento.
  bool listening = false;

  /// Escucha en pausa (p. ej. se quitaron los audífonos).
  bool paused = false;

  /// Hay audífonos conectados (cable, Bluetooth o USB).
  bool headphonesConnected = false;

  /// Pausar/reanudar la escucha al quitar/conectar audífonos.
  bool followHeadphones = true;

  /// Responder con voz. Lo controla el ajuste «Respuesta por voz».
  bool feedbackEnabled = true;

  /// SmartBuds está escuchando el nombre de una canción («¿Qué canción?»).
  bool askingForSong = false;

  /// Solo obedece después de «Oye música» (menos activaciones por error).
  bool requireWakeWord = false;

  /// «Solo mi voz».
  final SpeakerGuard guard = SpeakerGuard();

  /// Entrenamiento de «Solo mi voz» en curso: huellas recogidas.
  List<List<double>>? _enrollSamples;
  void Function(List<double> voiceprint)? _onEnrolled;
  static const enrollTarget = 3;

  bool get enrolling => _enrollSamples != null;
  int get enrollCount => _enrollSamples?.length ?? 0;

  /// Última frase rechazada por no ser tu voz.
  bool lastRejectedVoice = false;

  Future<bool> speakerAvailable() async {
    try {
      return await _method.invokeMethod<bool>('speakerAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Empieza a grabar tu voz: di «Cambia» 3 veces (no se ejecuta nada).
  void startEnrollment(void Function(List<double> voiceprint) onDone) {
    _enrollSamples = [];
    _onEnrolled = onDone;
    notifyListeners();
  }

  void cancelEnrollment() {
    _enrollSamples = null;
    _onEnrolled = null;
    notifyListeners();
  }

  /// Última frase oída (para mostrarla en pantalla).
  String lastHeard = '';

  /// Último comando reconocido.
  MusicCommand? lastCommand;

  /// Última búsqueda pedida por voz.
  SearchRequest? lastSearch;

  String? error;

  /// Sesión en la que ya se ejecutó una orden: evita repetirla con el
  /// resultado parcial y el final de la misma frase.
  int _handledSession = -1;

  /// Conecta los eventos nativos (estado de audífonos) sin activar el micrófono.
  void attach() {
    _sub ??= _events.receiveBroadcastStream().listen(
          (e) => handleEvent(Map<dynamic, dynamic>.from(e as Map)),
        );
  }

  Future<bool> hasPermission() async =>
      await _method.invokeMethod<bool>('hasPermission') ?? false;

  /// Pide micrófono (y notificaciones en Android 13+).
  Future<bool> requestPermission() async =>
      await _method.invokeMethod<bool>('requestPermission') ?? false;

  /// Al abrir la app: si ya hay permiso de micrófono, escucha sin tocar nada
  /// (manos libres). Si no hay permiso, espera a que el usuario toque el micro.
  Future<void> autoStart() async {
    if (enabled) return;
    try {
      if (await hasPermission()) await start();
    } catch (_) {}
  }

  Future<void> start() async {
    error = null;
    final available = await _method.invokeMethod<bool>('isAvailable') ?? false;
    if (!available) {
      error = defaultTargetPlatform == TargetPlatform.iOS
          ? 'El reconocimiento de voz del iPhone no está disponible ahora. '
              'Revisa Ajustes → Siri y Buscar y que haya conexión.'
          : 'Falta el modelo de voz. Ejecuta scripts/descargar-modelo-voz.ps1 '
              'y vuelve a instalar la app.';
      notifyListeners();
      return;
    }
    if (!await requestPermission()) {
      error = 'Sin permiso de micrófono, SmartBuds no puede escucharte.';
      notifyListeners();
      return;
    }
    attach();
    await _method.invokeMethod('start', {'grammar': CommandParser.voskGrammar});
    enabled = true;
    paused = false;
    notifyListeners();
  }

  Future<void> stop() async {
    enabled = false;
    listening = false;
    paused = false;
    await _method.invokeMethod('stop');
    notifyListeners();
  }

  Future<void> toggle() => enabled ? stop() : start();

  Future<void> setPaused(bool value) async {
    if (!enabled || paused == value) return;
    paused = value;
    await _method.invokeMethod('setPaused', {'paused': value});
    notifyListeners();
  }

  /// Respuesta hablada por los audífonos (si está activada).
  Future<void> speak(String text, {bool force = false}) async {
    if (!feedbackEnabled && !force) return;
    try {
      await _method.invokeMethod('speak', {'text': text});
    } catch (_) {}
  }

  /// Escucha una sola frase con el reconocedor preciso del sistema.
  Future<String?> listenOnce() async {
    try {
      return await _method.invokeMethod<String>('listenOnce');
    } catch (_) {
      return null;
    }
  }

  /// Público para poder probarlo sin el canal nativo.
  @visibleForTesting
  void handleEvent(Map<dynamic, dynamic> event) {
    final session = (event['session'] as int?) ?? 0;
    switch (event['type']) {
      case 'state':
        listening = event['listening'] == true;
        if (event['stopped'] == true) {
          // Detenido desde el botón de la notificación.
          enabled = false;
          paused = false;
        }
      case 'error':
        error = event['message'] as String?;
      case 'headphones':
        _onHeadphones(event['connected'] == true);
      case 'noise':
        final texts = ((event['texts'] as List?) ?? const []).cast<String>();
        if (texts.isNotEmpty) lastHeard = texts.first;
      case 'partial':
      case 'final':
        final texts = ((event['texts'] as List?) ?? const []).cast<String>();
        if (texts.isEmpty) break;
        lastHeard = texts.first;
        error = null;
        final spk = (event['spk'] as List?)?.map((e) => (e as num).toDouble()).toList();
        if (_enrollSamples != null) {
          _collectEnrollment(spk);
          break; // entrenando: no se ejecuta ninguna orden
        }
        if (session == _handledSession || askingForSong) break;
        lastRejectedVoice = !guard.accepts(spk);
        if (lastRejectedVoice) break; // no es tu voz
        for (final t in texts) {
          final intent = parser.parseIntent(t);
          // Con palabra de activación, solo «Oye música» abre la escucha.
          if (requireWakeWord && intent is! WakeIntent) continue;
          if (intent != null) {
            _handledSession = session;
            _dispatch(intent);
            break;
          }
        }
    }
    notifyListeners();
  }

  void _dispatch(VoiceIntent intent) {
    switch (intent) {
      case CommandIntent(:final command):
        final now = _clock();
        final isRepeat = command == lastCommand &&
            _lastCommandAt != null &&
            now.difference(_lastCommandAt!) < repeatCooldown;
        if (isRepeat) return;
        lastCommand = command;
        _lastCommandAt = now;
        unawaited(onCommand(command));
      case SearchIntent(:final request):
        if (onSearch == null) return;
        lastSearch = request;
        unawaited(onSearch!(request));
      case SearchPromptIntent():
        unawaited(_askForSong());
      case ArtistPromptIntent():
        unawaited(_askForArtist());
      case WakeIntent():
        unawaited(_listenAfterWake());
      case LikeIntent() ||
            DislikeIntent() ||
            FavoriteIntent() ||
            DiscoverIntent() ||
            ArtistIntent() ||
            MoodIntent():
        final handler = onIntent;
        if (handler != null) unawaited(handler(intent));
    }
  }

  void _collectEnrollment(List<double>? spk) {
    if (spk == null || spk.isEmpty) return;
    final samples = _enrollSamples!..add(spk);
    if (samples.length < enrollTarget) {
      unawaited(speak('Bien. Otra vez.', force: true));
      return;
    }
    final voiceprint = SpeakerGuard.average(samples);
    guard.voiceprint = voiceprint;
    final done = _onEnrolled;
    _enrollSamples = null;
    _onEnrolled = null;
    unawaited(speak('Listo, ya reconozco tu voz.', force: true));
    done?.call(voiceprint);
  }

  /// «Busca» → «¿Qué canción?» → escucha el nombre con el reconocedor preciso.
  Future<void> _askForSong() async {
    if (onSearch == null) return;
    askingForSong = true;
    notifyListeners();
    await speak('¿Qué canción?', force: true);
    final heard = await listenOnce();
    askingForSong = false;
    if (heard == null || heard.trim().isEmpty) {
      await speak('No te entendí.');
      notifyListeners();
      return;
    }
    lastHeard = heard;
    final request = parser.parseSearch('busca $heard') ?? SearchRequest(heard.trim());
    lastSearch = request;
    notifyListeners();
    await onSearch!(request);
  }

  /// «Oye música» → «¿Sí?» → una frase libre: orden, pedido o canción.
  Future<void> _listenAfterWake() async {
    askingForSong = true;
    notifyListeners();
    await speak('¿Sí?', force: true);
    final heard = await listenOnce();
    askingForSong = false;
    if (heard == null || heard.trim().isEmpty) {
      await speak('No te entendí.');
      notifyListeners();
      return;
    }
    lastHeard = heard;
    notifyListeners();
    final intent = parser.parseFree(heard);
    if (intent == null || intent is WakeIntent) return;
    _dispatch(intent);
  }

  /// «Pon algo de» → «¿De quién?» → escucha el artista con el reconocedor preciso.
  Future<void> _askForArtist() async {
    final handler = onIntent;
    if (handler == null) return;
    askingForSong = true;
    notifyListeners();
    await speak('¿De quién?', force: true);
    final heard = await listenOnce();
    askingForSong = false;
    if (heard == null || heard.trim().isEmpty) {
      await speak('No te entendí.');
      notifyListeners();
      return;
    }
    lastHeard = heard;
    notifyListeners();
    await handler(ArtistIntent(heard.trim()));
  }

  void _onHeadphones(bool connected) {
    final changed = connected != headphonesConnected;
    headphonesConnected = connected;
    if (!changed || !followHeadphones || !enabled) return;
    unawaited(setPaused(!connected));
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (enabled) _method.invokeMethod('stop');
    super.dispose();
  }
}
