import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../connectors/android_media/android_media_connector.dart';
import '../../connectors/deezer/similar_artists.dart';
import '../../connectors/weather/weather.dart';
import '../../connectors/youtube/youtube_search.dart';
import '../../core/models.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/settings/app_settings.dart';
import '../../core/telemetry/error_reporter.dart';
import '../../connectors/knowledge/music_knowledge.dart';
import '../automations/automation_runner.dart';
import '../brain/music_brain.dart';
import '../stats/evolution.dart';
import '../devices/detected_player_controller.dart';
import '../music_profile/music_profile.dart';

/// Coordina lo que pides por voz: reproductores, perfil musical y respuesta hablada.
class Assistant extends ChangeNotifier {
  Assistant({
    required this.controller,
    required this.profile,
    this.voice,
    this.finder,
    this.similar,
    this.media,
    this.settings,
    this.errors,
    this.weather,
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random(),
        _clock = clock ?? DateTime.now;

  final DetectedPlayerController controller;
  final MusicProfile profile;

  /// Búsqueda en YouTube (para descubrir canciones nuevas).
  final SongFinder? finder;

  /// Artistas parecidos (para «Pon algo nuevo»).
  final SimilarArtistsFinder? similar;
  final Random _random;
  final DateTime Function() _clock;

  /// Cerebro musical: decide qué recomendar y aprende de lo que pasa.
  late final MusicBrain brain = MusicBrain(profile: profile, settings: settings, similar: similar, clock: _clock);

  /// Recomendación del cerebro que está sonando (para aprender si acertó).
  /// [key] es la canción que de verdad empezó a sonar (la app puede llamarla distinto).
  ({String? key, RecKind kind, DateTime at})? _pendingRec;

  /// El momento según el cerebro: hora, ambiente reciente, perfil de uso y saltos.
  BrainContext get brainContext => BrainContext(
        now: _clock(),
        // Lo que pediste o, si no, el ambiente que se nota en lo último que sonó.
        mood: profile.currentMood ?? brain.ambience()?.mood,
        usageProfile: settings?.usageProfile,
        sessionSkips: profile.recentSkipStreak(),
      );

  /// «Para ti ahora»: sugerencias (no suenan solas).
  List<Recommendation> forYou({int n = 5}) => brain.recommend(brainContext, n: n);

  /// Pone una recomendación (porque la tocaste o la pediste) y aprende del resultado.
  Future<void> playRecommendation(Recommendation r) async {
    _pendingRec = (key: null, kind: r.kind, at: _clock());
    await handleSearch(SearchRequest(r.query));
  }

  /// Revisa si la última recomendación se terminó (acierto) o se saltó (fallo).
  void _evaluatePending(String? currentKey) {
    final p = _pendingRec;
    if (p == null || currentKey == null) return;
    if (p.key == null) {
      // Primera canción que suena después de recomendar: es la recomendada.
      if (_clock().difference(p.at) < const Duration(seconds: 45)) {
        _pendingRec = (key: currentKey, kind: p.kind, at: p.at);
      } else {
        _pendingRec = null;
      }
      return;
    }
    if (currentKey == p.key) return;
    for (final e in profile.history.reversed.take(30)) {
      if (e.key != p.key) continue;
      if (e.type == ListenEventType.complete || e.type == ListenEventType.like || e.type == ListenEventType.repeat) {
        brain.learn(p.kind, liked: true);
        break;
      }
      if (e.type == ListenEventType.skip || e.type == ListenEventType.dislike) {
        brain.learn(p.kind, liked: false);
        break;
      }
    }
    _pendingRec = null;
  }
  VoiceEngine? voice;

  /// Canal nativo (saltar en la canción, compartir). Null en pruebas.
  final AndroidMediaSource? media;

  /// Ajustes (radio, anunciar canciones…). Null = valores por defecto.
  final AppSettings? settings;

  /// Reportes anónimos de errores (opcional).
  final ErrorReporter? errors;

  /// Clima para sugerencias (opcional).
  final WeatherService? weather;

  // ------------------------------------------- Cola, audífonos, batería

  /// «Después pon …»: canciones en espera (la primera suena al cambiar la actual).
  final List<String> queue = [];

  /// Audífonos conectados ahora (nombre), o null.
  String? headphoneName;

  /// Batería baja y ahorro activo: menos voz y menos internet.
  bool lowBattery = false;
  int? batteryLevel;
  Timer? _batteryTimer;

  /// Sugerencia del clima (para la tarjeta de Inicio).
  WeatherMood? weatherMood;

  /// Arranca las tareas de fondo (batería, clima, audífonos). La llama main.dart.
  void startBackground() {
    unawaited(checkBattery());
    unawaited(refreshHeadphone());
    unawaited(refreshWeather());
    _batteryTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(checkBattery());
      unawaited(refreshWeather());
    });
  }

  Future<void> checkBattery() async {
    final b = await media?.battery();
    if (b == null) return;
    batteryLevel = b.level;
    final low = (settings?.batterySaver ?? true) && !b.charging && b.level <= 20;
    if (low != lowBattery) {
      lowBattery = low;
      notifyListeners();
    }
  }

  Future<void> refreshWeather() async {
    final w = weather;
    if (w == null || !(settings?.weatherSuggestions ?? false) || lowBattery) {
      if (weatherMood != null) {
        weatherMood = null;
        notifyListeners();
      }
      return;
    }
    final m = await w.current();
    if (m?.description != weatherMood?.description) {
      weatherMood = m;
      notifyListeners();
    }
  }

  Future<void> refreshHeadphone() async {
    final name = await media?.outputDevice();
    if (name != null) settings?.setLastHeadphone(name);
    if (name != headphoneName) {
      headphoneName = name;
      // Te subiste al carro: abre el modo carro si ese Bluetooth es el auto.
      final st = settings;
      if (name != null && st != null && st.moduleOn('car') && st.carAutoOpen && st.carDevices.contains(name)) {
        carMode = true;
      }
      notifyListeners();
    }
  }

  /// Tus automatizaciones y comandos personalizados (los ejecuta este asistente).
  AutomationRunner? automations;

  /// Modo carro abierto (pantalla grande y simple). La interfaz lo observa.
  bool carMode = false;

  void setCarMode(bool on) {
    if (carMode == on) return;
    carMode = on;
    notifyListeners();
  }

  Future<void> _say(String text) async => voice?.speak(text);

  /// Reproductor activo en este momento (o null).
  PlayerStatus? get active {
    final d = controller.detection;
    return d is PlayerDetected ? d.candidate.status : null;
  }

  // ---------------------------------------------------------------- Estado UI

  /// Hora en que se apaga la música (temporizador), o null.
  DateTime? sleepAt;
  Timer? _sleepTimer;
  Timer? _fadeTimer;

  /// «Deshacer» disponible hasta esta hora (tras un «Cambia»).
  DateTime? undoUntil;
  _UndoPoint? _undo;

  bool get canUndo => undoUntil != null && _clock().isBefore(undoUntil!);

  /// «Cambia», «Pausa»… Responde con voz solo si algo salió mal:
  /// cuando funciona, la música misma es la respuesta.
  /// Transición suave: baja el volumen, hace [action] y lo vuelve a subir.
  /// Solo Android (iOS no deja cambiar el volumen de otras apps).
  Future<T> _smooth<T>(Future<T> Function() action) async {
    final m = media;
    if (!(settings?.smoothTransitions ?? false) || m == null) return action();
    final before = await m.volumePercent();
    if (before == null || before < 10) return action();
    await m.fadeVolume((before * .3).round(), ms: 1200);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    final r = await action();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await m.fadeVolume(before, ms: 1500);
    return r;
  }

  Future<void> handleCommand(MusicCommand command) async {
    if (command == MusicCommand.next) _rememberForUndo();
    profile.noteCommand(command);
    final r = command == MusicCommand.next || command == MusicCommand.previous
        ? await _smooth(() => controller.sendVoice(command))
        : await controller.sendVoice(command);
    if (r == null) return;
    if (r.outcome == CommandOutcome.failed) {
      unawaited(errors?.report('comando_${command.name}', r.message) ?? Future.value());
    }
    switch (r.outcome) {
      case CommandOutcome.noPlayer:
        await _say('No hay música sonando.');
      case CommandOutcome.notAllowed:
        await _say('Ese reproductor no permite esa orden.');
      case CommandOutcome.failed:
      case CommandOutcome.permissionMissing:
        await _say('No pude hacerlo.');
      case CommandOutcome.needsChoice:
        await _say('Hay varios reproductores. Abre SmartBuds para elegir uno.');
      case CommandOutcome.verified:
      case CommandOutcome.sentUnverified:
        break;
    }
  }

  /// «Busca <canción>».
  Future<void> handleSearch(SearchRequest request) async {
    _lastSearchAt = _clock(); // la canción que llega ya se anuncia con «Reproduciendo…»
    final r = await controller.searchVoice(request);
    if (r == null) return;
    if (r.outcome == CommandOutcome.verified) {
      await _say(_spokenTitle(r.message) ?? 'Listo.');
    } else if (r.outcome == CommandOutcome.notAllowed) {
      await _say('Ese reproductor no permite buscar por voz.');
    } else if (r.outcome == CommandOutcome.failed) {
      unawaited(errors?.report('busqueda', r.message) ?? Future.value());
      await _say('No encontré esa canción.');
    }
    _lastSearchAt = _clock();
  }

  DateTime? _lastSearchAt;

  Future<void> handleIntent(VoiceIntent intent) async {
    switch (intent) {
      case LikeIntent():
        final t = profile.like();
        await _say(t == null ? 'No hay música sonando.' : 'Guardada en tus favoritas.');
      case DislikeIntent():
        profile.dislike();
        await _say('Entendido, la cambio.');
        await handleCommand(MusicCommand.next);
      case FavoriteIntent():
        await playFavorite();
      case DiscoverIntent():
        await discover();
      case ArtistIntent(:final artist):
        await handleSearch(SearchRequest(artist));
      case MoodIntent(:final mood, :final query):
        await playMood(mood, query);
      case CommandIntent(:final command):
        await handleCommand(command);
      case SearchIntent(:final request):
        await handleSearch(request);
      case NowPlayingIntent():
        await sayNowPlaying();
      case RestartIntent():
        await restart();
      case SeekIntent(:final seconds):
        await seekBy(seconds);
      case SleepIntent(:final minutes):
        if (minutes == 0) {
          await cancelSleep();
        } else {
          await sleepIn(minutes);
        }
      case UndoIntent():
        await undo();
      case ShareIntent():
        await shareCurrent();
      case RadioIntent(:final on):
        await setRadio(on);
      case VolumeIntent(:final percent):
        await setVolume(percent);
      case QueueIntent(:final query):
        if (query != null) await enqueue(query);
      case LyricsIntent(:final words):
        if (words != null) await handleSearch(SearchRequest(words));
      case BlockIntent(:final artist):
        await blockCurrent(artist: artist);
      case ForgottenIntent():
        await playForgotten();
      case ShareWeekIntent():
        await shareSummary(days: 7);
      case SimilarIntent():
        await playSimilar();
      case WhyIntent():
        await explainCurrent();
      case ArtistInfoIntent(:final artist):
        await tellAboutArtist(artist);
      case TasteEvolutionIntent():
        await _say(TasteEvolution.from(profile, now: _clock()).summary());
      case DurationIntent(:final minutes):
        await playFor(minutes);
      case UsageProfileIntent(:final profile):
        await useProfile(profile);
      case EnergyRampIntent():
        await energyRamp();
      case PrivateModeIntent(:final on):
        settings?.setPrivateMode(on);
        await _say(on
            ? 'Modo privado: no guardo lo que escuches.'
            : 'Listo, vuelvo a aprender de lo que escuchas.');
      case MacroIntent(:final id):
        await automations?.runById(id);
      case CarModeIntent(:final on) when on && !(settings?.moduleOn('car') ?? true):
        await _say('El modo carro está apagado en Extensiones.');
      case CarModeIntent(:final on):
        setCarMode(on);
        await _say(on
            ? 'Modo carro. Úsalo con la voz y mira la pantalla solo con el carro detenido.'
            : 'Listo, salí del modo carro.');
      case MultiIntent(:final parts):
        for (final p in parts) {
          await handleIntent(p);
        }
      case SearchPromptIntent() || ArtistPromptIntent() || WakeIntent() || StopListeningIntent():
        break; // lo resuelve el VoiceEngine (pregunta y escucha)
    }
  }

  // ---------------------------------------- Parecidas y «¿por qué esta?»

  /// Canciones parecidas a la que suena: artistas similares (Deezer) y su
  /// canción más popular. Sin datos de audio: el parecido es por artista.
  Future<List<({String artist, String title, String? picture})>> similarToCurrent() async {
    final a = active?.artist;
    final s = similar;
    if (a == null || a.isEmpty || s == null) return const [];
    try {
      final list = await s.similarTo(a, max: 8);
      return [
        for (final x in list)
          if (x.topTracks.isNotEmpty && !(settings?.isBlocked(null, x.name) ?? false))
            (artist: x.name, title: x.topTracks.first, picture: x.picture),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> playSimilar() async {
    final list = await similarToCurrent();
    if (list.isEmpty) {
      await _say('No encontré algo parecido. Prueba con «pon algo nuevo».');
      return;
    }
    final pick = list[_random.nextInt(min(4, list.length))];
    await _say('Te pongo ${pick.title}, de ${pick.artist}.');
    await handleSearch(SearchRequest('${pick.title} ${pick.artist}'));
  }

  /// Lista por duración: tus canciones para [minutes] (la primera suena, el resto en cola).
  Future<void> playFor(int minutes) async {
    final list = profile.playlistFor(minutes, random: _random);
    if (list.isEmpty) {
      await _say('Aún no conozco suficientes canciones tuyas. Escucha un poco más.');
      return;
    }
    String q(TrackStats t) => [t.title, if (t.artist != null) t.artist].join(' ');
    queue
      ..clear()
      ..addAll(list.skip(1).map(q));
    notifyListeners();
    await _say('Lista de $minutes minutos: ${list.length} canciones tuyas.');
    await handleSearch(SearchRequest(q(list.first)));
  }

  /// Perfil de uso: estudio (concentración), viaje (lista larga) o diario.
  Future<void> useProfile(String name) async {
    settings?.applyUsageProfile(name);
    radioSongs = 0;
    switch (name) {
      case 'estudio':
        await _say('Modo estudio: pocas interrupciones.');
        await playMood('para concentrarme', 'musica para concentrarse estudiar instrumental');
      case 'viaje':
        await _say('Modo viaje: te preparo dos horas de tu música.');
        await playFor(120);
      default:
        await _say('Modo diario.');
    }
  }

  /// De tranquila a fiesta: la primera suena ya y las demás suben la energía.
  Future<void> energyRamp() async {
    const steps = [
      ('tranquila', 'musica tranquila'),
      ('alegre', 'musica alegre'),
      ('para bailar', 'musica para bailar'),
      ('fiesta', 'reggaeton para fiesta exitos'),
    ];
    String pick((String, String) step) {
      final t = profile.pickMood(step.$1, random: _random);
      return t == null ? step.$2 : [t.title, if (t.artist != null) t.artist].join(' ');
    }

    queue
      ..clear()
      ..addAll(steps.skip(1).map(pick));
    notifyListeners();
    await _say('Empiezo tranquilo y voy subiendo la energía.');
    await handleSearch(SearchRequest(pick(steps.first)));
  }

  /// Vuelve a poner en la cola algo que se quitó (para «Deshacer»).
  void restoreToQueue(int index, String query) {
    queue.insert(index.clamp(0, queue.length), query);
    notifyListeners();
  }

  /// Conocimiento musical (Wikipedia + Deezer). Null = sin internet o desactivado.
  MusicKnowledge? knowledge;

  /// Lo último que se consultó de un artista (la interfaz lo muestra).
  final lastArtistInfo = ValueNotifier<ArtistInfo?>(null);

  /// Colaboraciones de un artista en TU música.
  List<String> collaborationsOf(String artist) => collaborationsIn(
        [for (final t in profile.tracks.values) (title: t.title, artist: t.artist)],
        artist,
      );

  /// «Cuéntame de Feid»: resumen con fuente, seguidores y colaboraciones en
  /// tu música. Si no hay datos confiables, lo dice (no inventa).
  Future<ArtistInfo?> tellAboutArtist(String? name) async {
    if (settings != null && !settings!.moduleOn('knowledge')) {
      await _say('El conocimiento musical está apagado en Extensiones.');
      return null;
    }
    final who = (name ?? active?.artist)?.trim();
    if (who == null || who.isEmpty) {
      await _say('Dime de qué artista quieres saber, o pon una canción.');
      return null;
    }
    final info = await knowledge?.artist(who);
    final collabs = collaborationsOf(who).take(3).toList();
    lastArtistInfo.value = info;
    final parts = <String>[];
    final summary = info?.shortSummary(settings?.shortReplies ?? false ? 1 : 2);
    if (summary != null) parts.add('Según Wikipedia: $summary');
    if (info?.fans != null && !(settings?.shortReplies ?? false)) {
      parts.add('Tiene ${_fansText(info!.fans!)} seguidores en Deezer.');
    }
    if (collabs.isNotEmpty) parts.add('En tu música aparece con ${collabs.join(', ')}.');
    await _say(parts.isEmpty ? 'No encontré información confiable de $who.' : parts.join(' '));
    return info;
  }

  static String _fansText(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)} millones de'
      : n >= 1000
          ? '${(n / 1000).round()} mil'
          : '$n';

  Future<void> explainCurrent() async {
    final a = active;
    final title = a?.title;
    if (a == null || title == null || title.isEmpty) {
      await _say('No hay música sonando.');
      return;
    }
    final reasons = profile.whyYouLike(MusicProfile.keyFor(title, a.artist));
    await _say(reasons.take(2).join(' '));
  }

  // --------------------------------------------------- Volumen exacto

  Future<void> setVolume(int percent) async {
    // Perfil de sonido: respeta el límite de volumen de estos audífonos.
    final cap = headphoneName == null ? null : settings?.volumeCaps[headphoneName];
    if (cap != null && percent > cap) {
      percent = cap;
      await _say('Lo dejo en $cap %, el límite que pusiste para estos audífonos.');
    }
    final ok = await media?.setVolumePercent(percent) ?? false;
    if (!ok) {
      await _say('Aquí no puedo fijar el volumen exacto. Usa los botones del teléfono.');
      return;
    }
    final h = headphoneName;
    if (h != null) settings?.setHeadphoneVolume(h, percent);
  }

  // ----------------------------------------------------------------- Cola

  Future<void> enqueue(String query) async {
    if (active?.isPlaying != true) {
      await handleSearch(SearchRequest(query)); // nada sonando: de una
      return;
    }
    queue.add(query);
    notifyListeners();
    await _say(queue.length == 1
        ? 'Listo, la pongo después de esta.'
        : 'Listo, va de ${queue.length} en la cola.');
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= queue.length) return;
    queue.removeAt(index);
    notifyListeners();
  }

  void moveInQueue(int from, int to) {
    if (from < 0 || from >= queue.length || to < 0 || to >= queue.length) return;
    queue.insert(to, queue.removeAt(from));
    notifyListeners();
  }

  Future<bool> _playNextQueued() async {
    if (queue.isEmpty) return false;
    final q = queue.removeAt(0);
    notifyListeners();
    await _smooth(() => handleSearch(SearchRequest(q)));
    return true;
  }

  // ---------------------------------------------------- «Nunca más esta»

  Future<void> blockCurrent({bool artist = false}) async {
    final a = active;
    final title = a?.title;
    if (a == null || title == null || title.isEmpty) {
      await _say('No hay música sonando.');
      return;
    }
    if (artist && (a.artist ?? '').isEmpty) {
      await _say('No sé qué artista es.');
      return;
    }
    settings?.block(title: title, artist: a.artist, wholeArtist: artist);
    profile.dislike();
    await _say(artist ? 'Listo, no vuelvo a poner a ${a.artist}.' : 'Listo, nunca más esta.');
    await controller.sendVoice(MusicCommand.next);
  }

  // ------------------------------------------------ Ambientes y olvidadas

  /// «Pon algo para entrenar»: tu lista automática si ya existe, si no, búsqueda.
  Future<void> playMood(String mood, String query) async {
    profile.setMood(mood);
    if (mood == 'nostálgica') {
      // Nostalgia de verdad: tus favoritas que hace tiempo no suenan.
      final old = forYou(n: 10).where((r) => r.kind == RecKind.rediscover).toList();
      if (old.isNotEmpty) {
        await _say('Te pongo una que hace rato no escuchas.');
        await playRecommendation(old[_random.nextInt(min(3, old.length))]);
        return;
      }
    }
    final pick = profile.pickMood(mood, random: _random);
    if (pick != null && _random.nextDouble() < 0.7) {
      await _say('Tu mezcla $mood.');
      await handleSearch(SearchRequest([pick.title, if (pick.artist != null) pick.artist].join(' ')));
      return;
    }
    await handleSearch(SearchRequest(query));
  }

  Future<void> playForgotten() async {
    final list = profile.forgottenFavorites();
    if (list.isEmpty) {
      await _say('No tienes favoritas olvidadas. Todo lo que te gusta suena seguido.');
      return;
    }
    final top = list.take(5).toList();
    final pick = top[_random.nextInt(top.length)];
    await _say('Hace rato no escuchas esta.');
    await handleSearch(SearchRequest([pick.title, if (pick.artist != null) pick.artist].join(' ')));
  }

  // ----------------------------------------------- Resumen para compartir

  /// Texto de tu resumen (semana o año) para enviar por WhatsApp, etc.
  String summaryText({int days = 7}) {
    final s = profile.summary(days: days);
    final period = days >= 365 ? 'Mi año' : (days > 7 ? 'Mis últimos $days días' : 'Mi semana');
    final lines = [
      '$period en música 🎧',
      '• ${s.plays} canciones · ~${s.minutes} minutos',
      if (s.topSong != null)
        '• Más escuchada: ${s.topSong!.title}${s.topSong!.artist == null ? '' : ' — ${s.topSong!.artist}'}',
      if (s.topArtist != null) '• Artista: ${s.topArtist}',
      if (profile.favoriteDaypart != null) '• Escucho más ${profile.favoriteDaypart!.label}',
      '',
      'Hecho con SmartBuds AI',
    ];
    return lines.join('\n');
  }

  Future<void> shareSummary({int days = 7}) async {
    final ok = await media?.shareText(summaryText(days: days)) ?? false;
    if (!ok) await _say('No pude abrir compartir.');
  }

  // ------------------------------------------------------- «¿Qué suena?»

  Future<void> sayNowPlaying() async {
    final a = active;
    final title = a?.title;
    if (a == null || title == null || title.isEmpty) {
      await _say('No hay música sonando.');
      return;
    }
    final artist = a.artist;
    await voice?.speak(
        artist == null || artist.isEmpty ? 'Suena $title.' : 'Suena $title, de $artist.',
        force: true);
  }

  // ------------------------------------------------ Repetir y adelantar

  Future<void> restart() async {
    final a = active;
    if (a == null) {
      await _say('No hay música sonando.');
      return;
    }
    final ok = await media?.seek(a.playerId, positionMs: 0) ?? false;
    if (!ok) {
      // Sin «saltar a»: la mayoría de reproductores reinicia con «anterior».
      await controller.sendVoice(MusicCommand.previous);
    }
    profile.markRepeat();
  }

  Future<void> seekBy(int seconds) async {
    final a = active;
    if (a == null) {
      await _say('No hay música sonando.');
      return;
    }
    final ok = await media?.seek(a.playerId, deltaMs: seconds * 1000) ?? false;
    if (!ok) await _say('Este reproductor no deja adelantar.');
  }

  // ------------------------------------------------------- Temporizador

  /// «Apaga en N minutos»: el último minuto baja el volumen poco a poco,
  /// pausa, y deja el volumen como estaba para la próxima vez.
  Future<void> sleepIn(int minutes) async {
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    final total = Duration(minutes: minutes);
    sleepAt = _clock().add(total);
    const fade = Duration(minutes: 1);
    _sleepTimer = Timer(total > fade ? total - fade : Duration.zero, _startFade);
    notifyListeners();
    await voice?.speak(
        minutes == 60 ? 'Listo, apago la música en una hora.' : 'Listo, apago la música en $minutes minutos.',
        force: true);
  }

  static const _fadeSteps = 5;

  void _startFade() {
    var step = 0;
    _fadeTimer = Timer.periodic(const Duration(seconds: 12), (t) async {
      step++;
      if (step <= _fadeSteps) {
        await controller.sendVoice(MusicCommand.volumeDown);
        return;
      }
      t.cancel();
      await controller.sendVoice(MusicCommand.pause);
      for (var i = 0; i < _fadeSteps; i++) {
        await controller.sendVoice(MusicCommand.volumeUp); // volumen de vuelta
      }
      sleepAt = null;
      notifyListeners();
    });
  }

  Future<void> cancelSleep() async {
    final had = sleepAt != null;
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    sleepAt = null;
    notifyListeners();
    await _say(had ? 'Temporizador cancelado.' : 'No había temporizador.');
  }

  // ------------------------------------------------------------- Deshacer

  void _rememberForUndo() {
    final a = active;
    if (a == null) return;
    _undo = _UndoPoint(a.playerId, a.trackKey, a.positionMs);
    undoUntil = _clock().add(const Duration(seconds: 20));
    notifyListeners();
  }

  /// «Deshacer»: vuelve a la canción de antes y al punto donde iba.
  Future<void> undo() async {
    final u = _undo;
    if (u == null || !canUndo) {
      await _say('No hay nada que deshacer.');
      return;
    }
    _undo = null;
    undoUntil = null;
    notifyListeners();
    profile.noteCommand(MusicCommand.previous);
    await controller.sendVoice(MusicCommand.previous);
    final pos = u.positionMs;
    if (pos != null && pos > 3000) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await media?.seek(u.playerId, positionMs: pos);
    }
  }

  // ------------------------------------------------------------- Compartir

  Future<void> shareCurrent() async {
    final a = active;
    final title = a?.title;
    if (a == null || title == null || title.isEmpty) {
      await _say('No hay música sonando.');
      return;
    }
    final song = [title, if ((a.artist ?? '').isNotEmpty) a.artist].join(' — ');
    final q = Uri.encodeQueryComponent([title, a.artist ?? ''].join(' ').trim());
    final text = 'Escucha «$song» 🎧\nhttps://music.youtube.com/search?q=$q\n\n'
        'Compartido con SmartBuds AI';
    final ok = await media?.shareText(text) ?? false;
    if (!ok) await _say('No pude abrir compartir.');
  }

  // --------------------------------------------- Radio, anuncios, aburrimiento

  Future<void> setRadio(bool on) async {
    if (on) radioSongs = 0;
    settings?.update(radioMode: on);
    if (on) {
      await voice?.speak('Radio activada. Pongo música sin parar.', force: true);
      if (active?.isPlaying != true) await nextRadioSong();
    } else {
      await voice?.speak('Radio desactivada.', force: true);
    }
  }

  /// Siguiente canción de la radio: 70 % favoritas, 30 % descubrimientos.
  /// Canciones puestas por la radio en esta sesión (para el descubrimiento gradual).
  int radioSongs = 0;

  /// Proporción de canciones nuevas: fija 30 %, o gradual de 10 % a 50 %.
  double get noveltyRatio {
    if (!(settings?.gradualDiscovery ?? true)) return 0.3;
    return (0.1 + 0.1 * (radioSongs ~/ 3)).clamp(0.1, 0.5).toDouble();
  }

  Future<void> nextRadioSong() async {
    final novelty = noveltyRatio;
    radioSongs++;
    if (_random.nextDouble() >= novelty && profile.pickFavorite() != null) {
      await playFavorite();
    } else {
      await discover();
    }
  }

  String? _lastKey;
  bool _wasPlaying = false;
  bool _boredHandled = false;

  /// Cada actualización del reproductor activo (la llama main.dart).
  void onPlayerUpdate(PlayerStatus? status) {
    final key = status?.trackKey;
    final playing = status?.isPlaying ?? false;
    final ownSearch =
        _lastSearchAt != null && _clock().difference(_lastSearchAt!) < const Duration(seconds: 10);

    // Canción nueva.
    if (playing && key != null && key != _lastKey) {
      _evaluatePending(key);
      final changed = _lastKey != null;
      _lastKey = key;
      if (settings?.isBlocked(status!.title, status.artist) ?? false) {
        unawaited(controller.sendVoice(MusicCommand.next)); // bloqueada: se salta sola
        _wasPlaying = playing;
        return;
      }
      if (changed && !ownSearch && queue.isNotEmpty) {
        unawaited(_playNextQueued());
        _wasPlaying = playing;
        return;
      }
      if (changed && (settings?.announceSongs ?? false) && !ownSearch && !lowBattery) {
        final t = status!.title ?? '';
        final a = status.artist ?? '';
        if (t.isNotEmpty) unawaited(_say(a.isEmpty ? t : '$t, de $a'));
      }
      _checkBoredom();
    }

    // Radio: la canción terminó y no sigue nada.
    final ended = _wasPlaying &&
        !playing &&
        (status == null || status.state == PlaybackState.stopped);
    if (ended && queue.isNotEmpty) {
      unawaited(_playNextQueued());
    } else if (ended && (settings?.radioMode ?? false)) {
      unawaited(nextRadioSong());
    }
    _wasPlaying = playing;
  }

  /// Tres saltos seguidos = te aburriste de ese estilo: algo distinto.
  void _checkBoredom() {
    final streak = profile.recentSkipStreak();
    if (streak < 3) {
      _boredHandled = false;
      return;
    }
    if (_boredHandled || lowBattery) return;
    _boredHandled = true;
    unawaited(() async {
      await _say('Te noto aburrido. Cambio de estilo.');
      await discover();
    }());
  }

  /// Al volver a conectar los audífonos: la música sigue donde iba.
  Future<void> onHeadphonesChanged(bool connected) async {
    if (!connected) {
      settings?.logConnection(false, headphoneName, _clock());
      headphoneName = null;
      notifyListeners();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refreshHeadphone();
    settings?.logConnection(true, headphoneName, _clock());
    // Audífonos preferidos: con otros, SmartBuds no toca volumen ni retoma.
    final preferred = settings?.preferredHeadphone;
    if (preferred != null && headphoneName != null && headphoneName != preferred) return;
    // Perfil por audífono: su volumen preferido.
    final saved = settings?.headphoneVolumes[headphoneName];
    final cap = settings?.volumeCaps[headphoneName];
    if (saved != null) {
      await media?.setVolumePercent(cap == null ? saved : min(saved, cap));
    } else if (cap != null) {
      final now = await media?.volumePercent();
      if (now != null && now > cap) await media?.setVolumePercent(cap);
    }
    if (!(settings?.resumeOnHeadphones ?? true)) return;
    final a = active;
    if (a == null || a.isPlaying) return;
    await Future<void>.delayed(const Duration(milliseconds: 800)); // que el audio cambie de salida
    await controller.sendVoice(MusicCommand.play);
  }

  /// Prueba de respuesta: cuánto tarda el reproductor en obedecer (pausa ↔ sigue).
  /// Devuelve los milisegundos, o null si no respondió en 4 s.
  Future<int?> measureLatency() async {
    final a = active;
    if (a == null) return null;
    final before = a.isPlaying;
    final sw = Stopwatch()..start();
    await controller.send(MusicCommand.togglePlayPause);
    int? ms;
    while (sw.elapsedMilliseconds < 4000) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (active?.isPlaying != before) {
        ms = sw.elapsedMilliseconds;
        break;
      }
    }
    // Dejarlo como estaba.
    if (ms != null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await controller.send(MusicCommand.togglePlayPause);
    }
    return ms;
  }

  /// Sugerencia según la hora (para la tarjeta de Inicio), o null.
  String? get contextSuggestion {
    if (active?.isPlaying == true) return null;
    final w = weatherMood;
    if (w != null) return '${w.description}: ¿te pongo música ${w.mood}?';
    if (profile.isUsualListeningTime()) return 'Es tu hora de música de siempre. ¿Pongo tus favoritas?';
    final fav = profile.favoriteDaypart;
    final now = Daypart.of(_clock());
    if (fav == null || fav != now || profile.pickFavorite() == null) return null;
    return 'Es de ${now.label.replaceFirst('en la ', '').replaceFirst('de ', '')}: '
        '¿te pongo lo que sueles escuchar a esta hora?';
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }

  /// «Pon algo que me guste»: elige de tu perfil y lo busca.
  Future<bool> playFavorite() async {
    final recs = forYou(n: 3);
    final ready = brain.readiness();
    if (recs.isNotEmpty && ready.learning) {
      await _say('Todavía te estoy conociendo, llevo ${ready.plays} canciones. Pongo una que te ha gustado.');
    }
    if (recs.isNotEmpty) {
      // Un poco de azar entre las 3 mejores para no repetir siempre la misma.
      final r = recs[_random.nextInt(recs.length)];
      await playRecommendation(r);
      return true;
    }
    final pick = profile.pickFavorite();
    if (pick == null) {
      await _say('Todavía estoy aprendiendo tus gustos. '
          'Sigue escuchando y dime «me gusta» cuando una canción te encante.');
      return false;
    }
    final query = [pick.title, if (pick.artist != null) pick.artist].join(' ');
    await handleSearch(SearchRequest(query));
    return true;
  }

  /// «Pon algo nuevo»: primero, una canción de un artista PARECIDO a los que
  /// más te gustan y que aún no escuchas; si no se puede, una canción que no
  /// conoces de tus artistas favoritos; y si aún no hay perfil, algo popular.
  Future<bool> discover() async {
    if (await _discoverSimilar()) return true;
    final f = finder;
    final artists = profile.topArtists(3).map((e) => e.$1).toList();
    if (f == null || artists.isEmpty) {
      await _say(artists.isEmpty
          ? 'Todavía no conozco tus gustos. Te pongo algo popular.'
          : 'Para descubrir música necesito la búsqueda de YouTube activada.');
      if (artists.isEmpty) await handleSearch(const SearchRequest('exitos del momento'));
      return false;
    }
    final known = profile.tracks.values
        .map((t) => t.title.toLowerCase())
        .where((t) => t.length > 2)
        .toList();
    for (final artist in artists) {
      final hits = await f.findMany(artist, max: 10);
      for (final hit in hits) {
        final title = hit.title.toLowerCase();
        if (known.any(title.contains)) continue; // ya la conoces
        await handleSearch(SearchRequest(hit.title));
        return true;
      }
    }
    await _say('Ya conoces lo mejor de tus artistas. Te pongo algo popular.');
    await handleSearch(const SearchRequest('exitos del momento'));
    return false;
  }

  Future<bool> _discoverSimilar() async {
    final s = similar;
    final top = profile.topArtists(3).map((e) => e.$1).toList();
    if (s == null || top.isEmpty) return false;
    final knownArtists = {
      for (final t in profile.tracks.values)
        if (t.artist != null) t.artist!.toLowerCase(),
    };
    final seed = top[_random.nextInt(top.length)];
    try {
      var candidates = (await s.similarTo(seed, max: 8))
          .where((a) =>
              a.topTracks.isNotEmpty &&
              !knownArtists.any((k) => k.contains(a.name.toLowerCase())) &&
              !(settings?.isBlocked(null, a.name) ?? false))
          .toList();
      // Nivel de descubrimiento: 0 = artistas conocidos, 2 = joyas ocultas.
      final level = settings?.discoveryLevel ?? 1;
      if (level != 1) {
        final filtered = candidates.where((a) {
          final f = a.fans;
          if (f == null) return true;
          return level == 0 ? f >= 1000000 : f < 300000;
        }).toList();
        if (filtered.isNotEmpty) candidates = filtered;
      }
      if (candidates.isEmpty) return false;
      final pick = candidates[_random.nextInt(candidates.length)];
      final song = pick.topTracks[_random.nextInt(pick.topTracks.length)];
      await _say('Te pongo ${pick.name}, se parece a $seed.');
      await handleSearch(SearchRequest('$song ${pick.name}'));
      return true;
    } catch (_) {
      return false; // sin internet o Deezer no respondió
    }
  }

  /// «Reproduciendo «Vacío» en YouTube Music.» → «Reproduciendo Vacío».
  static String? _spokenTitle(String message) {
    final m = RegExp(r'«(.+?)»').firstMatch(message);
    if (m == null) return null;
    final title = m.group(1)!
        .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '') // quita (Official Video), [Remix]…
        .trim();
    return 'Reproduciendo $title.';
  }
}

class _UndoPoint {
  const _UndoPoint(this.playerId, this.trackKey, this.positionMs);
  final String playerId;
  final String? trackKey;
  final int? positionMs;
}
