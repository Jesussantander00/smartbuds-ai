import '../../core/settings/app_settings.dart';
import '../music_profile/music_profile.dart';

/// Una insignia musical.
class Badge {
  const Badge(this.id, this.title, this.description, this.progress, this.goal);
  final String id;
  final String title;
  final String description;
  final int progress;
  final int goal;
  bool get earned => progress >= goal;
}

/// Un desafío de la semana.
class Challenge {
  const Challenge(this.title, this.progress, this.goal);
  final String title;
  final int progress;
  final int goal;
  bool get done => progress >= goal;
}

/// Insignias y desafíos: se calculan en el teléfono con tu propia escucha
/// (nada se comparte). Funciona en Android e iPhone, sin permisos.
class Achievements {
  Achievements(this.profile, this.settings, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final MusicProfile profile;
  final AppSettings settings;
  final DateTime Function() _clock;

  int _distinctArtists() => {for (final t in profile.tracks.values) if ((t.artist ?? '').isNotEmpty) t.artist!.toLowerCase()}.length;

  int _completes() => profile.tracks.values.fold<int>(0, (a, t) => a + t.completes);

  int _streakDays() {
    final days = {
      for (final e in profile.history)
        if (e.type == ListenEventType.play) DateTime(e.at.year, e.at.month, e.at.day),
    };
    var d = DateTime(_clock().year, _clock().month, _clock().day);
    if (!days.contains(d)) d = d.subtract(const Duration(days: 1)); // hoy aún no cuenta
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<Badge> badges({int mutualFriends = 0}) {
    final sent = settings.socialLog.where((e) => e.type == 'sent').length;
    return [
      Badge('explorer', 'Explorador', 'Escucha 10 artistas distintos', _distinctArtists(), 10),
      Badge('explorer2', 'Gran explorador', 'Escucha 50 artistas distintos', _distinctArtists(), 50),
      Badge('melomano', 'Melómano', 'Termina 100 canciones', _completes(), 100),
      Badge('chameleon', 'Camaleón', 'Arma mezclas de 4 ambientes', profile.moodTracks.length, 4),
      Badge('streak', 'Constante', 'Escucha 7 días seguidos', _streakDays(), 7),
      Badge('generous', 'Generoso', 'Envía 5 canciones a amigos', sent, 5),
      Badge('social', 'Buena compañía', 'Ten 3 amigos mutuos', mutualFriends, 3),
    ];
  }

  /// Inicio de la semana (lunes).
  DateTime get weekStart {
    final n = _clock();
    final today = DateTime(n.year, n.month, n.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  /// 3 desafíos de esta semana (cambian cada lunes).
  List<Challenge> weekly() {
    final from = weekStart;
    final week = profile.history.where((e) => !e.at.isBefore(from)).toList();
    // Artistas nuevos: su primera reproducción fue esta semana.
    final firstSeen = <String, DateTime>{};
    for (final e in profile.history) {
      if (e.type != ListenEventType.play) continue;
      final a = (profile.tracks[e.key]?.artist ?? '').toLowerCase();
      if (a.isEmpty) continue;
      final prev = firstSeen[a];
      if (prev == null || e.at.isBefore(prev)) firstSeen[a] = e.at;
    }
    final newArtists = firstSeen.values.where((d) => !d.isBefore(from)).length;
    final days = {for (final e in week) if (e.type == ListenEventType.play) e.at.weekday}.length;
    final completes = week.where((e) => e.type == ListenEventType.complete).length;
    final sent = settings.socialLog.where((e) => e.type == 'sent' && !e.at.isBefore(from)).length;
    final items = settings.socialLog.where((e) => e.type == 'item' && !e.at.isBefore(from)).length;
    final pool = [
      Challenge('Descubre 3 artistas nuevos', newArtists, 3),
      Challenge('Escucha música 5 días distintos', days, 5),
      Challenge('Termina 20 canciones', completes, 20),
      Challenge('Envía 2 canciones a amigos', sent, 2),
      Challenge('Agrega 3 canciones a una lista compartida', items, 3),
    ];
    // Rotación según la semana del año.
    final weekNo = from.difference(DateTime(from.year)).inDays ~/ 7;
    return [for (var i = 0; i < 3; i++) pool[(weekNo + i * 2) % pool.length]];
  }
}
