import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/voice_engine/command_parser.dart';
import '../assistant/assistant.dart';
import '../devices/detected_player_controller.dart';
import 'social_service.dart';

/// Escucha sincronizada: el anfitrión publica qué suena y en qué segundo; cada
/// invitado pone LA MISMA canción en SU propia app (con su cuenta) y se
/// acomoda al mismo segundo. No transmite audio: cada quien escucha en su app.
///
/// Funciona en Android (control de cualquier app) y en iPhone con Apple Music.
/// Saltar al segundo exacto solo si la app de música lo permite.
class ListenParty extends ChangeNotifier {
  ListenParty({required this.social, required this.assistant, required this.controller});

  final SocialService social;
  final Assistant assistant;
  final DetectedPlayerController controller;

  RoomState? room;
  String? status;
  Timer? _timer;
  String? _lastSent;
  String? _lastTrack;
  DateTime _lastSentAt = DateTime(2000);

  bool get active => room != null;

  /// Al abrir la app: ¿ya estaba en una sala?
  Future<void> resume() async {
    final r = await social.currentRoom();
    if (r != null) _start(r);
  }

  Future<void> host() async {
    final r = await social.openRoom();
    if (r != null) _start(r);
  }

  Future<bool> join(String code) async {
    final r = await social.joinRoom(code);
    if (r == null) return false;
    _start(r);
    return true;
  }

  Future<void> leave() async {
    final r = room;
    _timer?.cancel();
    room = null;
    status = null;
    notifyListeners();
    if (r != null) await social.leaveRoom(r);
  }

  void _start(RoomState r) {
    room = r;
    _lastTrack = null;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    unawaited(_tick());
    notifyListeners();
  }

  PlayerStatus? get _active => assistant.active;

  Future<void> _tick() async {
    final r = room;
    if (r == null) return;
    if (r.isHost) {
      await _publish();
    } else {
      await _follow();
    }
  }

  /// Anfitrión: publica la canción, la pausa/reproducción y saltos de posición.
  Future<void> _publish() async {
    final s = _active;
    final title = s?.title, artist = s?.artist;
    final playing = s?.isPlaying ?? false;
    final pos = s?.positionMs ?? 0;
    final key = '$title|$artist|$playing';
    final now = DateTime.now();
    // Publica si cambió algo o cada 20 s (para corregir desfases).
    if (key != _lastSent || now.difference(_lastSentAt) > const Duration(seconds: 20)) {
      _lastSent = key;
      _lastSentAt = now;
      await social.updateRoom(title, artist, pos, playing);
    }
    status = title == null ? 'Pon música para que tus amigos la escuchen contigo' : 'Compartiendo: $title';
    notifyListeners();
  }

  /// Invitado: sigue al anfitrión.
  Future<void> _follow() async {
    final r = await social.currentRoom();
    if (r == null) {
      // El anfitrión cerró la sala.
      _timer?.cancel();
      room = null;
      status = 'La sala se cerró.';
      notifyListeners();
      return;
    }
    room = r;
    final title = r.title;
    if (title == null) {
      status = 'Esperando a que el anfitrión ponga música…';
      notifyListeners();
      return;
    }
    final track = '$title|${r.artist}';
    final s = _active;
    if (track != _lastTrack) {
      _lastTrack = track;
      status = 'Poniendo $title…';
      notifyListeners();
      await assistant.handleSearch(SearchRequest([title, if (r.artist != null) r.artist].join(' ')));
      return; // en el próximo ciclo se ajusta el segundo
    }
    if (s == null) return;
    // Pausa / reproducción como el anfitrión.
    if (r.playing != s.isPlaying) {
      await controller.send(r.playing ? MusicCommand.play : MusicCommand.pause);
    }
    // Ajuste del segundo si van más de 8 s desfasados (si la app lo permite).
    final target = r.positionNow(DateTime.now());
    final mine = s.positionMs;
    if (r.playing && mine != null && (target - mine).abs() > 8000) {
      await assistant.media?.seek(s.playerId, positionMs: target);
    }
    status = 'Escuchando juntos: $title';
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
