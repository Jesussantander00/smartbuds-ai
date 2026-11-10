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

  // ------------------------------------------------- Personalización

  /// Secciones de Inicio en orden; las que no están, ocultas.
  static const allHomeSections = ['now', 'extras', 'queue', 'suggestion', 'search', 'favorite'];
  List<String> homeSections = [...allHomeSections];

  void setHomeSections(List<String> sections) {
    homeSections = [...sections];
    _persist();
    notifyListeners();
  }

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
    connectionLog = [HeadphoneEvent(at, connected, name), ...connectionLog].take(60).toList();
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
    final d = await _store.load() ?? const {};
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
    preferredHeadphone = d['preferredHeadphone'] as String?;
    final hs = (d['homeSections'] as List?)?.cast<String>();
    if (hs != null) homeSections = hs.where(allHomeSections.contains).toList();
    final qc = (d['quickCommands'] as List?)?.cast<String>();
    if (qc != null && qc.isNotEmpty) quickCommands = qc;
    compact = d['compact'] == true;
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
    blockedTracks = {...((d['blockedTracks'] as List?) ?? const []).cast<String>()};
    blockedArtists = {...((d['blockedArtists'] as List?) ?? const []).cast<String>()};
    authEmail = d['authEmail'] as String?;
    authUserId = d['authUserId'] as String?;
    authAccessToken = d['authAccessToken'] as String?;
    authRefreshToken = d['authRefreshToken'] as String?;
    final exp = d['authExpiresAt'] as String?;
    authExpiresAt = exp == null ? null : DateTime.tryParse(exp);
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

  Future<void> _persist() => _store.save({
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
        'preferredHeadphone': preferredHeadphone,
        'homeSections': homeSections,
        'quickCommands': quickCommands,
        'compact': compact,
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
        'blockedTracks': blockedTracks.toList(),
        'blockedArtists': blockedArtists.toList(),
        'authEmail': authEmail,
        'authUserId': authUserId,
        'authAccessToken': authAccessToken,
        'authRefreshToken': authRefreshToken,
        'authExpiresAt': authExpiresAt?.toIso8601String(),
      });

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
