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
  String themeMode = 'dark';
  int seedColor = 0xFF00B4D8;

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
    themeMode = (d['themeMode'] as String?) ?? 'dark';
    seedColor = (d['seedColor'] as num?)?.toInt() ?? 0xFF00B4D8;
    headphoneTaps = d['headphoneTaps'] != false;
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
  }) {
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
