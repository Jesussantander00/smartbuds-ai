import 'dart:async';
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

  /// Solo obedecer después de «Oye música».
  bool wakeWord = false;

  /// Dos toques al audífono = siguiente, tres = anterior.
  bool headphoneTaps = true;

  /// Palabra de activación propia (además de «Oye música»).
  String wakePhrase = '';

  /// Radio SmartBuds: al terminar una canción, elige la siguiente.
  bool radioMode = false;

  /// Decir el nombre de cada canción nueva.
  bool announceSongs = false;

  /// Retomar la música al volver a conectar los audífonos.
  bool resumeOnHeadphones = true;

  /// Enviar reportes anónimos de errores para mejorar la app.
  bool errorReports = true;

  /// Apariencia: 'system' | 'light' | 'dark', y color principal (ARGB).
  String themeMode = 'light';
  int seedColor = 0xFFE8833A;

  /// Respuestas habladas cortas (solo la primera frase).
  bool shortReplies = false;

  /// Qué tan desconocidos son los descubrimientos: 0 conocidos, 1 mixto, 2 joyas ocultas.
  int discoveryLevel = 1;

  /// Descubrimiento gradual: la radio empieza con tus conocidas y va metiendo
  /// más canciones nuevas a medida que sigue sonando.
  bool gradualDiscovery = true;

  /// Pausar la música al desconectar los audífonos.
  bool pauseOnUnplug = true;

  /// Pausar durante llamadas y retomar al colgar.
  bool pauseOnCalls = true;

  /// Con batería baja: menos voz y menos internet.
  bool batterySaver = true;

  /// Sugerencias según el clima (usa la ubicación aproximada por internet).
  bool weatherSuggestions = false;

  // ------------------------------------------------- Logros

  /// Acciones sociales propias (para insignias y desafíos): tipo y fecha.
  List<({String type, DateTime at})> socialLog = [];

  void logSocial(String type) {
    socialLog = [(type: type, at: DateTime.now()), ...socialLog].take(300).toList();
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------- Amigos

  /// Amigos agregados por código: código → (nombre, id).
  List<({String code, String name, String userId})> friends = [];

  void addFriend(String code, String name, String userId) {
    friends = [
      ...friends.where((f) => f.userId != userId),
      (code: code.toUpperCase(), name: name, userId: userId),
    ];
    _persist();
    notifyListeners();
  }

  void removeFriend(String userId) {
    friends = friends.where((f) => f.userId != userId).toList();
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------- Cerebro musical

  /// Cuánto confía el cerebro en cada fuente de recomendaciones (aprendido).
  Map<String, double> brainWeights = {};

  void setBrainWeight(String kind, double value) {
    brainWeights = {...brainWeights, kind: value};
    _persist();
  }

  // ------------------------------------------------- Privacidad

  /// Modo privado: lo que suene no se guarda ni cambia tus recomendaciones.
  bool privateMode = false;

  /// Última versión de «Novedades» que viste (para la insignia).
  int lastSeenChangelog = 0;

  void setPrivateMode(bool on) {
    privateMode = on;
    _persist();
    notifyListeners();
  }

  void markChangelogSeen(int version) {
    if (version <= lastSeenChangelog) return;
    lastSeenChangelog = version;
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------- Personalización

  /// Secciones de Inicio en orden; las que no están, ocultas.
  static const allHomeSections = ['now', 'foryou', 'extras', 'queue', 'suggestion', 'search', 'favorite'];
  /// Escritorios de Inicio: cada uno con sus secciones en orden (las que no
  /// están, ocultas). Casa, Trabajo, Estudio y Carro.
  static const desktopNames = {'casa': 'Casa', 'trabajo': 'Trabajo', 'estudio': 'Estudio', 'carro': 'Carro'};
  Map<String, List<String>> desktops = {
    'casa': [...allHomeSections],
    'trabajo': ['now', 'queue', 'search', 'foryou'],
    'estudio': ['now', 'foryou', 'queue'],
    'carro': ['now', 'favorite', 'extras'],
  };
  String activeDesktop = 'casa';

  /// Cambia de escritorio solo según el perfil de uso (estudio → Estudio…).
  bool autoDesktop = true;

  List<String> get homeSections => desktops[activeDesktop] ?? [...allHomeSections];

  void setHomeSections(List<String> sections) {
    desktops = {...desktops, activeDesktop: [...sections]};
    _persist();
    notifyListeners();
  }

  void setDesktop(String id) {
    if (!desktopNames.containsKey(id) || id == activeDesktop) return;
    activeDesktop = id;
    _persist();
    notifyListeners();
  }

  /// Escritorio que corresponde a un perfil de uso.
  static String desktopForProfile(String? profile) => switch (profile) {
        'estudio' => 'estudio',
        'viaje' => 'carro',
        _ => 'casa',
      };

  /// Comandos rápidos del Asistente (frases), en orden.
  static const defaultQuickCommands = [
    'que suena', 'pon mis favoritas', 'pon algo nuevo', 'pon mi radio',
    'pon favoritas olvidadas', 'apaga en treinta minutos',
  ];
  List<String> quickCommands = [...defaultQuickCommands];

  void setQuickCommands(List<String> list) {
    quickCommands = [...list];
    _persist();
    notifyListeners();
  }

  /// Interfaz compacta (pantallas pequeñas).
  bool compact = false;

  /// Carátulas vivas (respiran y brillan mientras suena).
  bool liveArt = true;

  /// Visualizador que sigue el audio real (Android; si el teléfono lo permite).
  bool realVisualizer = true;

  /// Colorear la tarjeta de Inicio con los colores de la carátula.
  bool dynamicColors = true;

  /// Perfil de uso activo: 'diario', 'estudio', 'viaje' (o null = personalizado).
  String? usageProfile;

  /// Aplica un perfil de uso: un grupo de ajustes pensado para la situación.
  void applyUsageProfile(String name) {
    switch (name) {
      case 'estudio': // pocas interrupciones
        shortReplies = true;
        announceSongs = false;
        radioMode = true;
        discoveryLevel = 0;
        voiceFeedback = true;
      case 'viaje': // música sin parar, descubrimientos y anuncios
        shortReplies = false;
        announceSongs = true;
        radioMode = true;
        discoveryLevel = 1;
        voiceFeedback = true;
      default: // diario
        name = 'diario';
        shortReplies = false;
        announceSongs = false;
        radioMode = false;
        discoveryLevel = 1;
        voiceFeedback = true;
    }
    usageProfile = name;
    // Escritorio de Inicio acorde al perfil (si lo dejaste automático).
    if (autoDesktop) activeDesktop = desktopForProfile(name);
    _persist();
    notifyListeners();
  }

  /// Audífonos preferidos: si hay, SmartBuds solo reacciona (volumen, retomar) con ellos.
  String? preferredHeadphone;

  void setPreferredHeadphone(String? name) {
    preferredHeadphone = name;
    _persist();
    notifyListeners();
  }

  /// Historial de conexiones de audífonos (más reciente primero, máx. 60).
  List<HeadphoneEvent> connectionLog = [];

  void logConnection(bool connected, String? name, DateTime at) {
    connectionLog = [HeadphoneEvent(at, connected, name), ...connectionLog].take(200).toList();
    _persist();
    notifyListeners();
  }

  /// Desconexiones reales: no cuenta cambiar de unos audífonos a otros
  /// (desconexión seguida en menos de 20 s por la conexión de OTROS audífonos).
  List<HeadphoneEvent> realDisconnections() {
    final out = <HeadphoneEvent>[];
    for (var i = 0; i < connectionLog.length; i++) {
      final e = connectionLog[i];
      if (e.connected) continue;
      final newer = i > 0 ? connectionLog[i - 1] : null;
      final switched = newer != null &&
          newer.connected &&
          newer.name != null &&
          e.name != null &&
          newer.name != e.name &&
          newer.at.difference(e.at) < const Duration(seconds: 20);
      if (!switched) out.add(e);
    }
    return out;
  }

  /// Conexión inestable: 3 o más desconexiones reales en los últimos 15 minutos.
  bool unstableConnection(DateTime now) =>
      realDisconnections().where((e) => now.difference(e.at) < const Duration(minutes: 15)).length >= 3;

  /// «Entendido» en el aviso: no lo repite durante una hora.
  DateTime? unstableDismissedUntil;

  bool showUnstableAlert(DateTime now) {
    final until = unstableDismissedUntil;
    return unstableConnection(now) && (until == null || now.isAfter(until));
  }

  void dismissUnstable(DateTime now) {
    unstableDismissedUntil = now.add(const Duration(hours: 1));
    notifyListeners();
  }

  /// Transición suave: baja el volumen antes de cambiar de canción y lo sube después.
  bool smoothTransitions = false;

  /// Límite de volumen por audífono (%) para cuidar los oídos. Nombre → límite.
  Map<String, int> volumeCaps = {};

  void setVolumeCap(String device, int? cap) {
    volumeCaps = {...volumeCaps}..remove(device);
    if (cap != null) volumeCaps[device] = cap.clamp(20, 100);
    _persist();
    notifyListeners();
  }

  /// Listas del curador (aprobadas por ti).
  List<Map<String, dynamic>> curatedLists = [];

  void setCuratedLists(List<Map<String, dynamic>> lists) {
    curatedLists = lists;
    _persist();
    notifyListeners();
  }

  /// Efectos visuales por canción: 0 apagados, 1 suaves, 2 normales, 3 intensos.
  int visualIntensity = 2;

  /// Multiplicador del efecto (0–2) según la intensidad elegida.
  double get visualFactor => const [0.0, .5, 1.0, 1.8][visualIntensity.clamp(0, 3)];

  /// Hogar inteligente: avisos (webhooks) que TÚ configuras en tu propio
  /// servicio (Home Assistant, IFTTT…). Cada uno: nombre, URL y cuándo se envía
  /// («track» = cada canción, «mood» = cambio de ambiente, «manual» = escena).
  List<Map<String, String>> homeHooks = [];

  void setHomeHooks(List<Map<String, String>> hooks) {
    visualIntensity = ((d['visualIntensity'] as num?) ?? 2).toInt().clamp(0, 3);
    curatedLists = [
      for (final l in (d['curatedLists'] as List?) ?? const [])
        if (l is Map) l.cast<String, dynamic>(),
    ];
    homeHooks = [for (final h in hooks.take(10)) Map.of(h)];
    _persist();
    notifyListeners();
  }

  /// Ecualizador de SmartBuds: encendido, perfil por audífono y por tipo de
  /// música (ambiente), y tu perfil manual (5 bandas en dB).
  bool eqEnabled = false;
  Map<String, String> eqByDevice = {};
  Map<String, String> eqByMood = {};
  List<double> eqCustom = [0, 0, 0, 0, 0];

  void setEqForDevice(String device, String? preset) {
    eqByDevice = {...eqByDevice}..remove(device);
    if (preset != null) eqByDevice[device] = preset;
    _persist();
    notifyListeners();
  }

  void setEqForMood(String mood, String? preset) {
    eqByMood = {...eqByMood}..remove(mood);
    if (preset != null) eqByMood[mood] = preset;
    _persist();
    notifyListeners();
  }

  void setEqCustom(List<double> db) {
    eqCustom = [for (final v in db.take(5)) v.clamp(-12.0, 12.0)];
    _persist();
    notifyListeners();
  }

  /// Voz personalizada: velocidad, tono y estilo («brief», «normal»,
  /// «conversational», «technical»).
  double speechRate = 1.0;
  double speechPitch = 1.0;
  String replyStyle = 'normal';

  /// Extensiones (módulos) que apagaste. Todas vienen encendidas.
  Set<String> disabledModules = {};

  bool moduleOn(String id) => !disabledModules.contains(id);

  void setModule(String id, bool on) {
    disabledModules = on ? ({...disabledModules}..remove(id)) : {...disabledModules, id};
    _persist();
    notifyListeners();
  }

  /// Copia de seguridad automática en la nube (una vez al día, con cuenta).
  bool autoBackup = true;
  DateTime? lastBackupAt;

  void markBackup(DateTime at) {
    lastBackupAt = at;
    _persist();
    notifyListeners();
  }

  /// Automatizaciones y comandos personalizados (JSON de cada una).
  List<Map<String, dynamic>> automations = [];

  void setAutomations(List<Map<String, dynamic>> list) {
    automations = list;
    _persist();
    notifyListeners();
  }

  /// Modo carro: dispositivos Bluetooth que son el auto (nombre) y si se abre solo.
  Set<String> carDevices = {};
  bool carAutoOpen = true;

  void setCarDevice(String name, bool isCar) {
    carDevices = isCar ? {...carDevices, name} : ({...carDevices}..remove(name));
    _persist();
    notifyListeners();
  }

  /// Centro multidispositivo: nombre visible de este teléfono y si comparte
  /// lo que suena con tus otros dispositivos (solo tu cuenta lo ve).
  String? deviceName;
  bool shareDevices = true;

  void setDeviceName(String? name) {
    final n = name?.trim();
    deviceName = (n == null || n.isEmpty) ? null : (n.length > 40 ? n.substring(0, 40) : n);
    _persist();
    notifyListeners();
  }

  /// Últimos audífonos usados (nombre).
  String? lastHeadphone;

  void setLastHeadphone(String name) {
    if (name == lastHeadphone) return;
    lastHeadphone = name;
    _persist();
    notifyListeners();
  }

  /// Volumen preferido por audífono (nombre → %).
  Map<String, int> headphoneVolumes = {};

  /// «Nunca más esta»: canciones (trackKey en minúsculas) y artistas bloqueados.
  Set<String> blockedTracks = {};
  Set<String> blockedArtists = {};

  bool isBlocked(String? title, String? artist) {
    final a = (artist ?? '').toLowerCase().trim();
    if (a.isNotEmpty && blockedArtists.contains(a)) return true;
    return blockedTracks.contains('${(title ?? '').toLowerCase().trim()}|$a');
  }

  void block({String? title, String? artist, bool wholeArtist = false}) {
    final a = (artist ?? '').toLowerCase().trim();
    if (wholeArtist) {
      if (a.isEmpty) return;
      blockedArtists = {...blockedArtists, a};
    } else {
      blockedTracks = {...blockedTracks, '${(title ?? '').toLowerCase().trim()}|$a'};
    }
    _persist();
    notifyListeners();
  }

  void unblock(String key, {bool artist = false}) {
    if (artist) {
      blockedArtists = {...blockedArtists}..remove(key);
    } else {
      blockedTracks = {...blockedTracks}..remove(key);
    }
    _persist();
    notifyListeners();
  }

  void setHeadphoneVolume(String device, int percent) {
    headphoneVolumes = {...headphoneVolumes, device: percent};
    _persist();
  }

  /// Sesión de la cuenta (Supabase Auth). Vacía = sin cuenta.
  String? authEmail;
  String? authUserId;
  String? authAccessToken;
  String? authRefreshToken;
  DateTime? authExpiresAt;

  bool get signedIn => authUserId != null && authRefreshToken != null;

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
    _apply(await _store.load() ?? const {});
  }

  void _apply(Map<String, dynamic> d) {
    onboardingDone = d['onboardingDone'] == true;
    voiceFeedback = d['voiceFeedback'] != false;
    followHeadphones = d['followHeadphones'] != false;
    _lastUsedPlayerId = d['lastUsedPlayerId'] as String?;
    voiceprint = (d['voiceprint'] as List?)?.map((e) => (e as num).toDouble()).toList();
    onlyMyVoice = d['onlyMyVoice'] == true;
    voiceThreshold = (d['voiceThreshold'] as num?)?.toDouble() ?? 0.5;
    wakeWord = d['wakeWord'] == true;
    wakePhrase = (d['wakePhrase'] as String?) ?? '';
    radioMode = d['radioMode'] == true;
    announceSongs = d['announceSongs'] == true;
    resumeOnHeadphones = d['resumeOnHeadphones'] != false;
    errorReports = d['errorReports'] != false;
    themeMode = (d['themeMode'] as String?) ?? 'light';
    seedColor = (d['seedColor'] as num?)?.toInt() ?? 0xFFE8833A;
    // Identidad visual nueva (vidrio cálido): se aplica una vez.
    if ((d['designVersion'] as num?) != 4) {
      themeMode = 'light';
      seedColor = 0xFFE8833A;
    }
    headphoneTaps = d['headphoneTaps'] != false;
    shortReplies = d['shortReplies'] == true;
    gradualDiscovery = d['gradualDiscovery'] != false;
    lastHeadphone = d['lastHeadphone'] as String?;
    smoothTransitions = d['smoothTransitions'] == true;
    volumeCaps = {
      for (final e in ((d['volumeCaps'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
    };
    preferredHeadphone = d['preferredHeadphone'] as String?;
    final hs = (d['homeSections'] as List?)?.cast<String>();
    if (hs != null) {
      final home = hs.where(allHomeSections.contains).toList();
      // Sección nueva «Para ti ahora»: se agrega una vez después de «Sonando ahora».
      if (d['hasForYou'] != true && !home.contains('foryou')) {
        final i = home.indexOf('now');
        home.insert(i < 0 ? 0 : i + 1, 'foryou');
      }
      desktops = {...desktops, 'casa': home};
    }
    final ds = d['desktops'];
    if (ds is Map) {
      for (final e in ds.entries) {
        if (desktopNames.containsKey(e.key) && e.value is List) {
          desktops = {...desktops, e.key as String: (e.value as List).cast<String>().where(allHomeSections.contains).toList()};
        }
      }
    }
    final ad = d['activeDesktop'] as String?;
    activeDesktop = desktopNames.containsKey(ad) ? ad! : 'casa';
    autoDesktop = d['autoDesktop'] != false;
    brainWeights = {
      for (final e in ((d['brainWeights'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    };
    final qc = (d['quickCommands'] as List?)?.cast<String>();
    if (qc != null && qc.isNotEmpty) quickCommands = qc;
    compact = d['compact'] == true;
    liveArt = d['liveArt'] != false;
    realVisualizer = d['realVisualizer'] != false;
    privateMode = d['privateMode'] == true;
    socialLog = [
      for (final e in (d['socialLog'] as List?) ?? const [])
        if (e is Map && e['at'] is String) (type: (e['t'] as String?) ?? '', at: DateTime.parse(e['at'] as String)),
    ];
    friends = [
      for (final f in (d['friends'] as List?) ?? const [])
        if (f is Map && f['id'] is String)
          (code: (f['code'] as String?) ?? '', name: (f['name'] as String?) ?? 'Amigo', userId: f['id'] as String),
    ];
    lastSeenChangelog = (d['lastSeenChangelog'] as num?)?.toInt() ?? 0;
    dynamicColors = d['dynamicColors'] != false;
    usageProfile = d['usageProfile'] as String?;
    connectionLog = [
      for (final e in (d['connectionLog'] as List?) ?? const [])
        if (e is Map && e['at'] is String)
          HeadphoneEvent(DateTime.parse(e['at'] as String), e['c'] == true, e['n'] as String?),
    ];
    discoveryLevel = (d['discoveryLevel'] as num?)?.toInt() ?? 1;
    pauseOnUnplug = d['pauseOnUnplug'] != false;
    pauseOnCalls = d['pauseOnCalls'] != false;
    batterySaver = d['batterySaver'] != false;
    weatherSuggestions = d['weatherSuggestions'] == true;
    headphoneVolumes = {
      for (final e in ((d['headphoneVolumes'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    disabledModules = {...((d['disabledModules'] as List?) ?? const []).cast<String>()};
    homeHooks = [
      for (final h in (d['homeHooks'] as List?) ?? const [])
        if (h is Map) h.map((k, v) => MapEntry('$k', '$v')),
    ];
    eqEnabled = d['eqEnabled'] == true;
    eqByDevice = ((d['eqByDevice'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    eqByMood = ((d['eqByMood'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    final custom = (d['eqCustom'] as List?)?.map((e) => (e as num).toDouble()).toList();
    eqCustom = custom != null && custom.length == 5 ? custom : [0, 0, 0, 0, 0];
    speechRate = ((d['speechRate'] as num?) ?? 1.0).toDouble().clamp(0.5, 2.0);
    speechPitch = ((d['speechPitch'] as num?) ?? 1.0).toDouble().clamp(0.5, 2.0);
    replyStyle = (d['replyStyle'] as String?) ?? 'normal';
    autoBackup = d['autoBackup'] != false;
    lastBackupAt = DateTime.tryParse('${d['lastBackupAt'] ?? ''}');
    automations = [
      for (final a in (d['automations'] as List?) ?? const [])
        if (a is Map) a.cast<String, dynamic>(),
    ];
    carDevices = {...((d['carDevices'] as List?) ?? const []).cast<String>()};
    carAutoOpen = d['carAutoOpen'] != false;
    deviceName = d['deviceName'] as String?;
    shareDevices = d['shareDevices'] != false;
    blockedTracks = {...((d['blockedTracks'] as List?) ?? const []).cast<String>()};
    blockedArtists = {...((d['blockedArtists'] as List?) ?? const []).cast<String>()};
    authEmail = d['authEmail'] as String?;
    authUserId = d['authUserId'] as String?;
    authAccessToken = d['authAccessToken'] as String?;
    authRefreshToken = d['authRefreshToken'] as String?;
    final exp = d['authExpiresAt'] as String?;
    authExpiresAt = exp == null ? null : DateTime.tryParse(exp);
    deviceId = (d['deviceId'] as String?) ?? _newId();
    if (d['deviceId'] == null) unawaited(_persist());
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
    bool? wakeWord,
    bool? headphoneTaps,
    String? wakePhrase,
    bool? radioMode,
    bool? announceSongs,
    bool? resumeOnHeadphones,
    bool? errorReports,
    String? themeMode,
    int? seedColor,
    bool? shortReplies,
    bool? gradualDiscovery,
    bool? compact,
    bool? smoothTransitions,
    bool? carAutoOpen,
    bool? autoBackup,
    bool? eqEnabled,
    bool? autoDesktop,
    int? visualIntensity,
    double? speechRate,
    double? speechPitch,
    String? replyStyle,
    bool? shareDevices,
    bool? liveArt,
    bool? realVisualizer,
    bool? dynamicColors,
    int? discoveryLevel,
    bool? pauseOnUnplug,
    bool? pauseOnCalls,
    bool? batterySaver,
    bool? weatherSuggestions,
  }) {
    if (shortReplies != null) this.shortReplies = shortReplies;
    if (gradualDiscovery != null) this.gradualDiscovery = gradualDiscovery;
    if (compact != null) this.compact = compact;
    if (smoothTransitions != null) this.smoothTransitions = smoothTransitions;
    if (carAutoOpen != null) this.carAutoOpen = carAutoOpen;
    if (autoBackup != null) this.autoBackup = autoBackup;
    if (eqEnabled != null) this.eqEnabled = eqEnabled;
    if (autoDesktop != null) this.autoDesktop = autoDesktop;
    if (visualIntensity != null) this.visualIntensity = visualIntensity.clamp(0, 3);
    if (speechRate != null) this.speechRate = speechRate.clamp(0.5, 2.0);
    if (speechPitch != null) this.speechPitch = speechPitch.clamp(0.5, 2.0);
    if (replyStyle != null) this.replyStyle = replyStyle;
    if (shareDevices != null) this.shareDevices = shareDevices;
    if (liveArt != null) this.liveArt = liveArt;
    if (realVisualizer != null) this.realVisualizer = realVisualizer;
    if (dynamicColors != null) this.dynamicColors = dynamicColors;
    if (discoveryLevel != null) this.discoveryLevel = discoveryLevel;
    if (pauseOnUnplug != null) this.pauseOnUnplug = pauseOnUnplug;
    if (pauseOnCalls != null) this.pauseOnCalls = pauseOnCalls;
    if (batterySaver != null) this.batterySaver = batterySaver;
    if (weatherSuggestions != null) this.weatherSuggestions = weatherSuggestions;
    if (wakePhrase != null) this.wakePhrase = wakePhrase;
    if (radioMode != null) this.radioMode = radioMode;
    if (announceSongs != null) this.announceSongs = announceSongs;
    if (resumeOnHeadphones != null) this.resumeOnHeadphones = resumeOnHeadphones;
    if (errorReports != null) this.errorReports = errorReports;
    if (themeMode != null) this.themeMode = themeMode;
    if (seedColor != null) this.seedColor = seedColor;
    if (wakeWord != null) this.wakeWord = wakeWord;
    if (headphoneTaps != null) this.headphoneTaps = headphoneTaps;
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

  /// Guarda o borra (null) la sesión de la cuenta.
  void setSession({
    String? email,
    String? userId,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) {
    authEmail = email;
    authUserId = userId;
    authAccessToken = accessToken;
    authRefreshToken = refreshToken;
    authExpiresAt = expiresAt;
    _persist();
    notifyListeners();
  }

  Future<void> _persist() => _store.save(toMap());

  /// Ajustes que NO viajan en la copia de seguridad: sesión de la cuenta,
  /// identidad de este teléfono, tu huella de voz y estado de la bienvenida.
  static const _notInBackup = {
    'authEmail', 'authUserId', 'authAccessToken', 'authRefreshToken', 'authExpiresAt',
    'deviceId', 'deviceName', 'voiceprint', 'onlyMyVoice', 'lastUsedPlayerId', 'onboardingDone',
    'lastBackupAt', 'homeHooks',
  };

  /// Tus preferencias para la copia de seguridad (sin datos de sesión ni de voz).
  Map<String, dynamic> backupPreferences() =>
      Map.of(toMap())..removeWhere((k, _) => _notInBackup.contains(k));

  /// Restaura preferencias de una copia; conserva la sesión y lo propio de este teléfono.
  Future<void> restorePreferences(Map<String, dynamic> prefs) async {
    final merged = toMap();
    prefs.forEach((k, v) {
      if (!_notInBackup.contains(k)) merged[k] = v;
    });
    _apply(merged);
    await _persist();
  }

  /// Todos los ajustes como mapa (para guardar y para la copia de seguridad).
  Map<String, dynamic> toMap() => {
        'onboardingDone': onboardingDone,
        'voiceFeedback': voiceFeedback,
        'followHeadphones': followHeadphones,
        'lastUsedPlayerId': _lastUsedPlayerId,
        'deviceId': deviceId,
        'voiceprint': voiceprint,
        'onlyMyVoice': onlyMyVoice,
        'voiceThreshold': voiceThreshold,
        'wakeWord': wakeWord,
        'headphoneTaps': headphoneTaps,
        'wakePhrase': wakePhrase,
        'radioMode': radioMode,
        'announceSongs': announceSongs,
        'resumeOnHeadphones': resumeOnHeadphones,
        'errorReports': errorReports,
        'themeMode': themeMode,
        'seedColor': seedColor,
        'designVersion': 4,
        'shortReplies': shortReplies,
        'gradualDiscovery': gradualDiscovery,
        'lastHeadphone': lastHeadphone,
        'smoothTransitions': smoothTransitions,
        'volumeCaps': volumeCaps,
        'preferredHeadphone': preferredHeadphone,
        'homeSections': desktops['casa'],
        'desktops': desktops,
        'activeDesktop': activeDesktop,
        'autoDesktop': autoDesktop,
        'hasForYou': true,
        'brainWeights': brainWeights,
        'quickCommands': quickCommands,
        'compact': compact,
        'liveArt': liveArt,
        'realVisualizer': realVisualizer,
        'privateMode': privateMode,
        'socialLog': [for (final e in socialLog) {'t': e.type, 'at': e.at.toIso8601String()}],
        'friends': [for (final f in friends) {'code': f.code, 'name': f.name, 'id': f.userId}],
        'lastSeenChangelog': lastSeenChangelog,
        'dynamicColors': dynamicColors,
        'usageProfile': usageProfile,
        'connectionLog': [
          for (final e in connectionLog) {'at': e.at.toIso8601String(), 'c': e.connected, 'n': e.name},
        ],
        'discoveryLevel': discoveryLevel,
        'pauseOnUnplug': pauseOnUnplug,
        'pauseOnCalls': pauseOnCalls,
        'batterySaver': batterySaver,
        'weatherSuggestions': weatherSuggestions,
        'headphoneVolumes': headphoneVolumes,
        'automations': automations,
        'disabledModules': disabledModules.toList(),
        'visualIntensity': visualIntensity,
        'curatedLists': curatedLists,
        'homeHooks': homeHooks,
        'eqEnabled': eqEnabled,
        'eqByDevice': eqByDevice,
        'eqByMood': eqByMood,
        'eqCustom': eqCustom,
        'speechRate': speechRate,
        'speechPitch': speechPitch,
        'replyStyle': replyStyle,
        'autoBackup': autoBackup,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
        'carDevices': carDevices.toList(),
        'carAutoOpen': carAutoOpen,
        'deviceName': deviceName,
        'shareDevices': shareDevices,
        'blockedTracks': blockedTracks.toList(),
        'blockedArtists': blockedArtists.toList(),
        'authEmail': authEmail,
        'authUserId': authUserId,
        'authAccessToken': authAccessToken,
        'authRefreshToken': authRefreshToken,
        'authExpiresAt': authExpiresAt?.toIso8601String(),
      };

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// Una conexión o desconexión de audífonos.
class HeadphoneEvent {
  const HeadphoneEvent(this.at, this.connected, this.name);
  final DateTime at;
  final bool connected;
  final String? name;
}
