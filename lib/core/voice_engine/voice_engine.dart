import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../storage/json_store.dart';
import 'command_parser.dart';
import 'speaker_guard.dart';

/// Estados de Jarvis (máquina de estados de la escucha):
/// desactivado, preparado, escuchando, procesando, ejecutando, respondiendo,
/// recuperando (reabriendo el micrófono) y error (necesita que toques «Reintentar»).
enum JarvisState { off, ready, listening, processing, working, responding, recovering, error }

/// Cómo responde SmartBuds en voz alta.
enum ReplyStyle { brief, normal, conversational, technical }

/// Una línea del historial de voz: lo que dijiste y lo que respondió SmartBuds.
class VoiceLogEntry {
  VoiceLogEntry(this.at, this.heard, this.action);
  final DateTime at;
  final String heard;

  /// Qué entendió («Siguiente canción», «Buscar: Ojalá»…).
  final String action;

  /// Lo que SmartBuds dijo después (si dijo algo).
  String? reply;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'heard': heard,
        'action': action,
        if (reply != null) 'reply': reply,
      };

  static VoiceLogEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return VoiceLogEntry(at, '${j['heard'] ?? ''}', '${j['action'] ?? ''}')..reply = j['reply'] as String?;
  }
}

/// Memoria corta de la conversación: de quién se habló y qué se hizo hace poco.
/// Permite «busca Feid» → «pon una de él» → «no, la otra». Solo en memoria.
class ConversationMemory {
  ConversationMemory(this._clock);
  final DateTime Function() _clock;

  /// Cuánto dura el contexto («él» deja de ser Feid tras este tiempo).
  static const window = Duration(minutes: 10);

  /// Hasta cuándo se puede corregir la última acción con «no, la otra».
  static const correctWindow = Duration(seconds: 90);

  String? _artist;
  DateTime? _artistAt;
  VoiceIntent? _last;
  DateTime? _lastAt;

  /// Artista del que se habló hace poco (o null).
  String? get artist =>
      _artistAt != null && _clock().difference(_artistAt!) < window ? _artist : null;

  /// Última acción que se puede corregir (o null si pasó mucho tiempo).
  VoiceIntent? get lastAction =>
      _lastAt != null && _clock().difference(_lastAt!) < correctWindow ? _last : null;

  void noteArtist(String? name) {
    final n = name?.trim();
    if (n == null || n.isEmpty) return;
    _artist = n;
    _artistAt = _clock();
  }

  void remember(VoiceIntent intent) {
    switch (intent) {
      case ArtistIntent(:final artist):
        noteArtist(artist);
      case ArtistInfoIntent(:final artist):
        noteArtist(artist);
      default:
        break;
    }
    if (_correctable(intent)) {
      _last = intent;
      _lastAt = _clock();
    }
  }

  void forget() {
    _artist = null;
    _artistAt = null;
    _last = null;
    _lastAt = null;
  }

  static bool _correctable(VoiceIntent i) => switch (i) {
        CommandIntent() ||
        SearchIntent() ||
        ArtistIntent() ||
        MoodIntent() ||
        LyricsIntent() ||
        SimilarIntent() ||
        DiscoverIntent() ||
        FavoriteIntent() ||
        ForgottenIntent() ||
        DurationIntent() ||
        VolumeIntent() ||
        UsageProfileIntent() =>
          true,
        _ => false,
      };

  /// Qué hacer ante «no, la otra»: la orden contraria (si existe) y si hay
  /// que preguntar qué querías.
  static ({VoiceIntent? fix, String? ask, String? say}) correctionFor(VoiceIntent? last) {
    switch (last) {
      case null:
        return (fix: null, ask: null, say: 'No tengo nada reciente que corregir.');
      case CommandIntent(:final command):
        final inverse = switch (command) {
          MusicCommand.next => MusicCommand.previous,
          MusicCommand.previous => MusicCommand.next,
          MusicCommand.volumeUp => MusicCommand.volumeDown,
          MusicCommand.volumeDown => MusicCommand.volumeUp,
          MusicCommand.pause => MusicCommand.play,
          MusicCommand.play => MusicCommand.pause,
          MusicCommand.togglePlayPause => MusicCommand.togglePlayPause,
        };
        return (fix: CommandIntent(inverse), ask: null, say: 'Perdón, lo corrijo.');
      case VolumeIntent():
        return (fix: null, ask: '¿A qué volumen lo dejo?', say: null);
      case UsageProfileIntent():
        return (fix: const UsageProfileIntent('diario'), ask: null, say: 'Perdón, vuelvo al modo diario.');
      default:
        return (fix: null, ask: 'Perdón. ¿Qué querías escuchar?', say: null);
    }
  }
}

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

  /// Tus comandos personalizados: se revisan antes que los de SmartBuds.
  VoiceIntent? Function(String heard)? customIntent;

  /// Artista que suena ahora (para «pon una de él»).
  String? Function()? currentArtist;

  /// Modo privado: no se guarda lo que dices en el historial.
  bool Function()? isPrivate;

  /// Dónde se guarda el historial de conversación (null = solo en memoria).
  JsonStore? historyStore;

  /// Memoria corta de la conversación (contexto y correcciones).
  late final ConversationMemory conversation = ConversationMemory(_clock);

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

  /// Escucha abierta: sin música sonando, también se aceptan pedidos
  /// libres («pon Ojalá de Ryan Castro») sin decir antes «Oye música».
  bool freeMode = false;

  /// Palabra de activación propia (además de «Oye música»), tal como se dice.
  String customWake = '';

  /// Avisa al conectar/desconectar audífonos (p. ej. para retomar la música).
  void Function(bool connected)? onHeadphonesChanged;

  /// Frases para el reconocedor: órdenes + la palabra de activación propia.
  List<String> get grammar => [
        ...CommandParser.voskGrammar.where((p) => p != '[unk]'),
        if (customWake.trim().isNotEmpty) customWake.trim().toLowerCase(),
        '[unk]',
      ];

  /// Cambia la palabra de activación propia y recarga el reconocedor.
  Future<void> setCustomWake(String phrase) async {
    customWake = phrase.trim();
    CommandParser.customWakePhrases =
        customWake.isEmpty ? {} : {CommandParser.normalize(customWake)};
    if (!enabled) return;
    try {
      await _method.invokeMethod('setGrammar', {'grammar': grammar});
    } catch (_) {}
  }

  /// Con música sonando: solo órdenes (gramática). Sin música: escucha abierta.
  Future<void> setFreeMode(bool value) async {
    if (freeMode == value) return;
    freeMode = value;
    if (!enabled) return;
    try {
      await _method.invokeMethod('setGrammarEnabled', {'enabled': !value});
    } catch (_) {}
  }

  /// Respuestas cortas: solo la primera frase de cada respuesta hablada.
  bool shortReplies = false;

  /// Voz personalizada: velocidad y tono (0,5–2,0) y estilo de respuesta.
  double speechRate = 1.0;
  double speechPitch = 1.0;
  ReplyStyle replyStyle = ReplyStyle.normal;
  int _replies = 0;

  /// SmartBuds está hablando (lo avisa el lado nativo).
  bool speaking = false;

  /// Procesando/ejecutando una orden hasta este momento (para el núcleo de Jarvis).
  DateTime? _busyUntil;
  DateTime? _processingUntil;

  /// El lado nativo está reabriendo el micrófono.
  bool recovering = false;

  /// La escucha se cayó y no se pudo recuperar sola: hace falta «Reintentar».
  bool failed = false;

  /// Desde cuándo debería estar escuchando y no lo está (vigilante).
  DateTime? _deafSince;
  int _recoverAttempts = 0;
  DateTime? _lastRecoverAt;
  Timer? _watchdog;

  /// Vigilante: cada cuánto revisa y cuánto tolera sin escuchar antes de reabrir.
  static const watchdogEvery = Duration(seconds: 4);
  static const deafTolerance = Duration(seconds: 8);
  static const maxRecoverAttempts = 3;

  /// Registro de diagnóstico de la escucha (cambios de estado, errores, recuperaciones).
  final List<({DateTime at, String what})> diagnostics = [];

  void _diag(String what) {
    diagnostics.insert(0, (at: _clock(), what: what));
    if (diagnostics.length > 40) diagnostics.removeLast();
  }

  /// Estado de Jarvis (para el núcleo animado y los avisos).
  JarvisState get jarvisState {
    if (!enabled) return JarvisState.off;
    if (failed) return JarvisState.error;
    if (speaking) return JarvisState.responding;
    final now = _clock();
    final busy = _busyUntil;
    if (busy != null && now.isBefore(busy)) return JarvisState.working;
    final proc = _processingUntil;
    if (proc != null && now.isBefore(proc)) return JarvisState.processing;
    if (paused) return JarvisState.ready;
    if (listening) return JarvisState.listening;
    if (recovering || _recoverAttempts > 0) return JarvisState.recovering;
    return JarvisState.ready;
  }

  /// Revisa que la escucha siga viva y la reabre si se cayó en silencio.
  /// Sin reintentos infinitos: tras [maxRecoverAttempts] pasa a error.
  @visibleForTesting
  Future<void> checkHealth() async {
    if (!enabled || paused || speaking || askingForSong || failed) {
      _deafSince = null;
      return;
    }
    if (listening) {
      _deafSince = null;
      _recoverAttempts = 0;
      return;
    }
    final now = _clock();
    _deafSince ??= now;
    if (now.difference(_deafSince!) < deafTolerance) return;
    // Pausas crecientes entre intentos: 8 s, 16 s, 32 s.
    final wait = deafTolerance * (1 << _recoverAttempts);
    if (_lastRecoverAt != null && now.difference(_lastRecoverAt!) < wait) return;
    if (_recoverAttempts >= maxRecoverAttempts) {
      failed = true;
      error ??= 'Jarvis dejó de escuchar y no pudo recuperarse. Toca «Reintentar».';
      _diag('Error: no se pudo recuperar la escucha');
      notifyListeners();
      return;
    }
    _recoverAttempts++;
    _lastRecoverAt = now;
    _diag('Recuperando la escucha (intento $_recoverAttempts)');
    notifyListeners();
    try {
      await _method.invokeMethod<bool>('ensure');
    } catch (_) {}
  }

  /// Al volver a la app o tras un error: comprueba y reabre la escucha.
  Future<void> ensureListening() async {
    if (!enabled) return;
    _recoverAttempts = 0;
    _deafSince = null;
    try {
      await _method.invokeMethod<bool>('ensure');
    } catch (_) {}
  }

  /// «Reintentar»: borra el error y vuelve a empezar.
  Future<void> retry() async {
    failed = false;
    error = null;
    _recoverAttempts = 0;
    _lastRecoverAt = null;
    _deafSince = null;
    _diag('Reintentar');
    notifyListeners();
    if (enabled) {
      await ensureListening();
    } else {
      await start();
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(watchdogEvery, (_) => unawaited(checkHealth()));
  }

  /// Pasos de la última orden encadenada (para el panel de acciones).
  List<String> lastPlan = const [];

  /// Mientras corre una orden encadenada, las respuestas se juntan en una sola.
  List<String>? _batch;

  /// Últimas órdenes entendidas (la más reciente primero).
  final List<VoiceLogEntry> history = [];
  static const historyMax = 100;

  void _log(VoiceIntent intent) {
    if (isPrivate?.call() ?? false) return; // modo privado: no se guarda
    history.insert(0, VoiceLogEntry(_clock(), lastHeard, describe(intent)));
    if (history.length > historyMax) history.removeLast();
    _saveHistory();
  }

  /// Carga el historial de conversación guardado en el teléfono.
  Future<void> loadHistory() async {
    final data = await historyStore?.load();
    final list = (data?['entries'] as List?) ?? const [];
    history
      ..clear()
      ..addAll(list.map(VoiceLogEntry.fromJson).whereType<VoiceLogEntry>().take(historyMax));
    notifyListeners();
  }

  void _saveHistory() {
    final store = historyStore;
    if (store == null) return;
    unawaited(store.save({'entries': [for (final e in history) e.toJson()]}).catchError((_) {}));
  }

  /// Borra todo el historial de conversación (y el contexto).
  Future<void> clearHistory() async {
    history.clear();
    conversation.forget();
    await historyStore?.save({'entries': <Object>[]});
    notifyListeners();
  }

  /// Texto legible de una orden (para el historial).
  static String describe(VoiceIntent intent) => switch (intent) {
        CommandIntent(:final command) => switch (command) {
            MusicCommand.next => 'Siguiente canción',
            MusicCommand.previous => 'Canción anterior',
            MusicCommand.pause => 'Pausa',
            MusicCommand.play => 'Continuar',
            MusicCommand.togglePlayPause => 'Pausa / continuar',
            MusicCommand.volumeUp => 'Subir volumen',
            MusicCommand.volumeDown => 'Bajar volumen',
          },
        SearchIntent(:final request) => 'Buscar: ${request.query}',
        SearchPromptIntent() => 'Buscar…',
        ArtistPromptIntent() => 'Artista…',
        WakeIntent() => 'Activación',
        NowPlayingIntent() => '¿Qué suena?',
        RestartIntent() => 'Repetir',
        SeekIntent(:final seconds) => seconds > 0 ? 'Adelantar' : 'Atrasar',
        SleepIntent(:final minutes) =>
          minutes == 0 ? 'Cancelar temporizador' : 'Apagar en $minutes min',
        UndoIntent() => 'Deshacer',
        ShareIntent() => 'Compartir canción',
        RadioIntent(:final on) => on ? 'Radio activada' : 'Radio desactivada',
        LikeIntent() => 'Me gusta',
        DislikeIntent() => 'No me gusta',
        FavoriteIntent() => 'Mis favoritas',
        DiscoverIntent() => 'Algo nuevo',
        ArtistIntent(:final artist) => 'Artista: $artist',
        MoodIntent(:final mood) => 'Ambiente $mood',
        VolumeIntent(:final percent) => 'Volumen al $percent %',
        QueueIntent(:final query) => query == null ? 'Poner después…' : 'Después: $query',
        LyricsIntent(:final words) => words == null ? 'Por la letra…' : 'Letra: «$words»',
        BlockIntent(:final artist) => artist ? 'Bloquear artista' : 'Nunca más esta',
        MultiIntent(:final parts) => parts.map(describe).join(' + '),
        StopListeningIntent() => 'Dejar de escuchar',
        HomeSceneIntent(:final name) => 'Escena $name',
        ForgottenIntent() => 'Favoritas olvidadas',
        ShareWeekIntent() => 'Compartir mi semana',
        SimilarIntent() => 'Algo parecido',
        WhyIntent() => '¿Por qué esta?',
        DurationIntent(:final minutes) => 'Lista de $minutes min',
        UsageProfileIntent(:final profile) => 'Modo $profile',
        EnergyRampIntent() => 'Subir la energía',
        PrivateModeIntent(:final on) => on ? 'Modo privado' : 'Salir del modo privado',
        CarModeIntent(:final on) => on ? 'Modo carro' : 'Salir del modo carro',
        MacroIntent(:final name) => name,
        ArtistInfoIntent(:final artist) => artist == null ? 'Sobre este artista' : 'Sobre $artist',
        TasteEvolutionIntent() => 'Tu evolución musical',
        FollowUpArtistIntent() => 'Otra del mismo artista',
        CorrectionIntent() => 'Corrección',
        ClarifyIntent() => 'Pregunta: ¿qué quieres?',
        DiagnoseIntent() => 'Autodiagnóstico',
      };

  /// Primera frase de [text] (para respuestas cortas).
  /// Aplica el estilo de respuesta. [action] es lo que entendió (para el técnico).
  static String styleReply(String text, ReplyStyle style, {String? action, int n = 0}) {
    switch (style) {
      case ReplyStyle.brief:
        return shorten(text);
      case ReplyStyle.conversational:
        const openers = ['¡Listo! ', 'Claro. ', 'Perfecto, ', 'Va. '];
        final t = text.trimLeft();
        if (t.startsWith('¡') || RegExp(r'^(Listo|Claro|Perfecto|Va|Hecho)\b').hasMatch(t)) return text;
        final o = openers[n % openers.length];
        return o.endsWith(', ') && t.isNotEmpty ? '$o${t[0].toLowerCase()}${t.substring(1)}' : '$o$t';
      case ReplyStyle.technical:
        return action == null ? text : 'Orden: $action. $text';
      case ReplyStyle.normal:
        return text;
    }
  }

  static String shorten(String text) {
    final m = RegExp(r'^(.+?[.!?])(\s|$)').firstMatch(text.trim());
    return m == null ? text : m.group(1)!;
  }

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

  /// Permiso de micrófono sin lanzar errores (null si no se pudo consultar).
  Future<bool?> micPermission() async {
    try {
      return await _method.invokeMethod<bool>('hasPermission');
    } catch (_) {
      return null;
    }
  }

  /// Abre los ajustes de SmartBuds en el sistema (para dar el permiso de micrófono).
  Future<bool> openAppSettings() async {
    try {
      return await _method.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pide micrófono (y notificaciones en Android 13+).
  Future<bool> requestPermission() async =>
      await _method.invokeMethod<bool>('requestPermission') ?? false;

  /// Al abrir la app: si ya hay permiso de micrófono, escucha sin tocar nada
  /// (manos libres). Si no hay permiso, espera a que el usuario toque el micro.
  Future<void> autoStart() async {
    if (enabled) return;
    try {
      if (await hasPermission()) {
        await start();
      } else {
        _diag('Sin permiso de micrófono: hay que tocar el micrófono una vez');
        notifyListeners();
      }
    } catch (e) {
      _diag('No se pudo iniciar solo: $e');
      notifyListeners();
    }
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
    try {
      await _method.invokeMethod('start', {'grammar': grammar, 'grammarEnabled': !freeMode});
    } on PlatformException catch (e) {
      error = e.code == 'PERMISSION'
          ? 'Sin permiso de micrófono, SmartBuds no puede escucharte.'
          : 'No se pudo abrir el micrófono: ${e.message ?? e.code}';
      _diag('Error al iniciar: $error');
      notifyListeners();
      return;
    }
    enabled = true;
    paused = false;
    failed = false;
    _recoverAttempts = 0;
    _deafSince = null;
    _diag('Escucha continua activada');
    _startWatchdog();
    notifyListeners();
  }

  /// Ejecuta una orden encadenada paso por paso y confirma al final con una
  /// sola respuesta: «Listo, hice 3 cosas: …».
  @visibleForTesting
  Future<void> runChain(List<VoiceIntent> parts, {Duration gap = const Duration(milliseconds: 900)}) async {
    lastPlan = [for (final p in parts) describe(p)];
    notifyListeners();
    _batch = [];
    try {
      for (final p in parts) {
        _dispatch(p, log: false);
        await Future<void>.delayed(gap);
      }
    } finally {
      _batch = null;
    }
    final steps = lastPlan;
    final list = steps.length == 1
        ? steps.first
        : '${steps.sublist(0, steps.length - 1).join(', ')} y ${steps.last}';
    await speak('Listo, hice ${steps.length} cosas: ${list.toLowerCase()}.');
  }

  /// Ejecuta una orden desde el panel de acciones (como si la hubieras dicho).
  void runIntent(VoiceIntent intent) => _dispatch(intent);

  Future<void> stop() async {
    enabled = false;
    listening = false;
    paused = false;
    recovering = false;
    failed = false;
    _watchdog?.cancel();
    _watchdog = null;
    _diag('Escucha detenida');
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
    final batch = _batch;
    if (batch != null && !force) {
      batch.add(text);
      return;
    }
    final recent = history.isNotEmpty && _clock().difference(history.first.at) < const Duration(seconds: 20);
    var said = styleReply(text, replyStyle, action: recent ? history.first.action : null, n: _replies++);
    if (shortReplies) said = shorten(said);
    if (history.isNotEmpty &&
        _clock().difference(history.first.at) < const Duration(seconds: 20)) {
      if (history.first.reply == null) {
        history.first.reply = said;
        _saveHistory();
      }
    }
    try {
      await _method.invokeMethod('speak', {'text': said, 'rate': speechRate, 'pitch': speechPitch});
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
        final was = listening;
        listening = event['listening'] == true;
        recovering = event['recovering'] == true;
        if (listening) {
          _deafSince = null;
          _recoverAttempts = 0;
          failed = false;
        }
        if (was != listening) _diag(listening ? 'Escuchando' : (recovering ? 'Reabriendo el micrófono' : 'Micrófono cerrado'));
        if (event['stopped'] == true) {
          // Detenido desde el botón de la notificación.
          enabled = false;
          paused = false;
          _watchdog?.cancel();
          _watchdog = null;
        }
      case 'speaking':
        speaking = event['on'] == true;
        if (speaking) _busyUntil = null;
      case 'error':
        error = event['message'] as String?;
        if (error != null) _diag('Error: $error');
        // Error que el teléfono no puede resolver solo (modelo, permisos, reintentos agotados).
        if (event['fatal'] == true) failed = true;
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
        _processingUntil = _clock().add(const Duration(milliseconds: 700));
        final spk = (event['spk'] as List?)?.map((e) => (e as num).toDouble()).toList();
        if (_enrollSamples != null) {
          _collectEnrollment(spk);
          break; // entrenando: no se ejecuta ninguna orden
        }
        if (session == _handledSession || askingForSong) break;
        lastRejectedVoice = !guard.accepts(spk);
        if (lastRejectedVoice) break; // no es tu voz
        for (final t in texts) {
          final custom = requireWakeWord ? null : customIntent?.call(t);
          final intent = custom ??
              (freeMode && !requireWakeWord ? parser.parseOpen(t) : parser.parseIntent(t));
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

  void _dispatch(VoiceIntent intent, {bool log = true}) {
    if (log) _log(intent);
    conversation.remember(intent);
    // Núcleo de Jarvis: «ejecutando» unos segundos (hasta que responda).
    _busyUntil = _clock().add(const Duration(milliseconds: 2500));
    notifyListeners(); // el núcleo se redibuja solo y vuelve a «escuchando» al pasar el tiempo
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
      case QueueIntent(query: null):
        unawaited(_askThen('¿Qué pongo después?', (h) => QueueIntent(h)));
      case LyricsIntent(words: null):
        unawaited(_askThen('¿Qué dice la letra?', (h) => LyricsIntent(h)));
      case MultiIntent(:final parts):
        unawaited(runChain(parts));
      case FollowUpArtistIntent():
        final who = currentArtist?.call() ?? conversation.artist;
        if (who == null || who.trim().isEmpty) {
          unawaited(_askForArtist());
        } else {
          _dispatch(ArtistIntent(who), log: false);
        }
      case CorrectionIntent():
        unawaited(_correct());
      case ClarifyIntent():
        unawaited(_askThen('¿Qué artista o género quieres?',
            (h) => parser.parseIntent('pon algo $h') ?? parser.parseFree(h) ?? SearchIntent(SearchRequest(h))));
      case StopListeningIntent():
        unawaited(() async {
          await speak('Dejo de escuchar. Toca el micrófono cuando quieras.', force: true);
          await stop();
        }());
      case VolumeIntent() ||
            QueueIntent() ||
            LyricsIntent() ||
            BlockIntent() ||
            ForgottenIntent() ||
            ShareWeekIntent() ||
            SimilarIntent() ||
            WhyIntent() ||
            DurationIntent() ||
            UsageProfileIntent() ||
            EnergyRampIntent() ||
            PrivateModeIntent() ||
            CarModeIntent() ||
            MacroIntent() ||
            ArtistInfoIntent() ||
            TasteEvolutionIntent() ||
            DiagnoseIntent() ||
            HomeSceneIntent() ||
            NowPlayingIntent() ||
            RestartIntent() ||
            SeekIntent() ||
            SleepIntent() ||
            UndoIntent() ||
            ShareIntent() ||
            RadioIntent() ||
            LikeIntent() ||
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

  /// «No, la otra» / «eso no era»: deshace o corrige la última acción.
  Future<void> _correct() async {
    final last = conversation.lastAction;
    final plan = ConversationMemory.correctionFor(last);
    final say = plan.say;
    if (say != null) await speak(say);
    final fix = plan.fix;
    if (fix != null) {
      _lastCommandAt = null; // la corrección no cuenta como repetición
      _dispatch(fix, log: false);
    }
    final ask = plan.ask;
    if (ask == null) return;
    if (last is VolumeIntent) {
      await _askThen(ask, (h) => VolumeIntent(parser.parseVolume('volumen al $h') ?? 50));
    } else {
      await _askThen(ask, (h) => parser.parseFree(h) ?? SearchIntent(SearchRequest(h)));
    }
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
    conversation.remember(SearchIntent(request));
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

  /// Pregunta [question], escucha la respuesta y la convierte en una orden.
  Future<void> _askThen(String question, VoiceIntent Function(String heard) build) async {
    final handler = onIntent;
    if (handler == null) return;
    askingForSong = true;
    notifyListeners();
    await speak(question, force: true);
    final heard = await listenOnce();
    askingForSong = false;
    if (heard == null || heard.trim().isEmpty) {
      await speak('No te entendí.');
      notifyListeners();
      return;
    }
    lastHeard = heard;
    final intent = build(heard.trim());
    _log(intent);
    conversation.remember(intent);
    notifyListeners();
    await handler(intent);
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
    final intent = ArtistIntent(heard.trim());
    _log(intent);
    conversation.remember(intent);
    notifyListeners();
    await handler(intent);
  }

  void _onHeadphones(bool connected) {
    final changed = connected != headphonesConnected;
    headphonesConnected = connected;
    if (changed) onHeadphonesChanged?.call(connected);
    if (!changed || !followHeadphones || !enabled) return;
    unawaited(setPaused(!connected));
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _sub?.cancel();
    if (enabled) _method.invokeMethod('stop');
    super.dispose();
  }
}
