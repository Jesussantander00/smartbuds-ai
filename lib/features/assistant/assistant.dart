import '../../connectors/youtube/youtube_search.dart';
import '../../core/models.dart';
import '../../core/voice_engine/command_parser.dart';
import '../../core/voice_engine/voice_engine.dart';
import '../devices/detected_player_controller.dart';
import '../music_profile/music_profile.dart';

/// Coordina lo que pides por voz: reproductores, perfil musical y respuesta hablada.
class Assistant {
  Assistant({
    required this.controller,
    required this.profile,
    this.voice,
    this.finder,
  });

  final DetectedPlayerController controller;
  final MusicProfile profile;

  /// Búsqueda en YouTube (para descubrir canciones nuevas).
  final SongFinder? finder;
  VoiceEngine? voice;

  Future<void> _say(String text) async => voice?.speak(text);

  /// «Cambia», «Pausa»… Responde con voz solo si algo salió mal:
  /// cuando funciona, la música misma es la respuesta.
  Future<void> handleCommand(MusicCommand command) async {
    profile.noteCommand(command);
    final r = await controller.sendVoice(command);
    if (r == null) return;
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
    final r = await controller.searchVoice(request);
    if (r == null) return;
    if (r.outcome == CommandOutcome.verified) {
      await _say(_spokenTitle(r.message) ?? 'Listo.');
    } else if (r.outcome == CommandOutcome.notAllowed) {
      await _say('Ese reproductor no permite buscar por voz.');
    } else if (r.outcome == CommandOutcome.failed) {
      await _say('No encontré esa canción.');
    }
  }

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
      case SearchPromptIntent() || ArtistPromptIntent():
        break; // lo resuelve el VoiceEngine (pregunta y escucha)
    }
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

  /// «Pon algo nuevo»: una canción que no has escuchado de tus artistas
  /// favoritos (o, si aún no hay perfil, algo popular).
  Future<bool> discover() async {
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
