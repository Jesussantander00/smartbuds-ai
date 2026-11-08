import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../connectors/android_media/android_media_connector.dart';
import '../../connectors/deezer/similar_artists.dart';
import '../../connectors/youtube/youtube_search.dart';
import '../../core/models.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../../core/player_detector/active_player_detector.dart';
import '../../core/settings/app_settings.dart';
import '../../core/telemetry/error_reporter.dart';
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
  VoiceEngine? voice;

  /// Canal nativo (saltar en la canción, compartir). Null en pruebas.
  final AndroidMediaSource? media;

  /// Ajustes (radio, anunciar canciones…). Null = valores por defecto.
  final AppSettings? settings;

  /// Reportes anónimos de errores (opcional).
  final ErrorReporter? errors;

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
  Future<void> handleCommand(MusicCommand command) async {
    if (command == MusicCommand.next) _rememberForUndo();
    profile.noteCommand(command);
    final r = await controller.sendVoice(command);
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
      case MoodIntent(:final query):
        await handleSearch(SearchRequest(query));
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
      case SearchPromptIntent() || ArtistPromptIntent() || WakeIntent():
        break; // lo resuelve el VoiceEngine (pregunta y escucha)
    }
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
    settings?.update(radioMode: on);
    if (on) {
      await voice?.speak('Radio activada. Pongo música sin parar.', force: true);
      if (active?.isPlaying != true) await nextRadioSong();
    } else {
      await voice?.speak('Radio desactivada.', force: true);
    }
  }

  /// Siguiente canción de la radio: 70 % favoritas, 30 % descubrimientos.
  Future<void> nextRadioSong() async {
    if (_random.nextDouble() < 0.7 && profile.pickFavorite() != null) {
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
      final changed = _lastKey != null;
      _lastKey = key;
      if (changed && (settings?.announceSongs ?? false) && !ownSearch) {
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
    if (ended && (settings?.radioMode ?? false)) unawaited(nextRadioSong());
    _wasPlaying = playing;
  }

  /// Tres saltos seguidos = te aburriste de ese estilo: algo distinto.
  void _checkBoredom() {
    final streak = profile.recentSkipStreak();
    if (streak < 3) {
      _boredHandled = false;
      return;
    }
    if (_boredHandled) return;
    _boredHandled = true;
    unawaited(() async {
      await _say('Te noto aburrido. Cambio de estilo.');
      await discover();
    }());
  }

  /// Al volver a conectar los audífonos: la música sigue donde iba.
  Future<void> onHeadphonesChanged(bool connected) async {
    if (!connected || !(settings?.resumeOnHeadphones ?? true)) return;
    final a = active;
    if (a == null || a.isPlaying) return;
    await Future<void>.delayed(const Duration(milliseconds: 800)); // que el audio cambie de salida
    await controller.sendVoice(MusicCommand.play);
  }

  /// Sugerencia según la hora (para la tarjeta de Inicio), o null.
  String? get contextSuggestion {
    if (active?.isPlaying == true) return null;
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
    super.dispose();
  }

  /// «Pon algo que me guste»: elige de tu perfil y lo busca.
  Future<bool> playFavorite() async {
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
      final candidates = (await s.similarTo(seed))
          .where((a) =>
              a.topTracks.isNotEmpty &&
              !knownArtists.any((k) => k.contains(a.name.toLowerCase())))
          .toList();
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
