import '../models.dart';

/// Pedido de búsqueda: «busca Ojalá de Ryan Castro en Apple Music».
class SearchRequest {
  const SearchRequest(this.query, {this.appPackage, this.appName});
  final String query;

  /// App pedida explícitamente («en Apple Music»); null = la activa.
  final String? appPackage;
  final String? appName;

  @override
  String toString() => 'SearchRequest($query, $appPackage)';
}

/// Lo que el usuario pidió por voz.
sealed class VoiceIntent {
  const VoiceIntent();
}

/// «Cambia», «Pausa», «Sube»…
class CommandIntent extends VoiceIntent {
  const CommandIntent(this.command);
  final MusicCommand command;
}

/// «Busca Ojalá de Ryan Castro [en Apple Music]».
class SearchIntent extends VoiceIntent {
  const SearchIntent(this.request);
  final SearchRequest request;
}

/// «Busca» solo: SmartBuds pregunta «¿Qué canción?» y escucha el nombre.
class SearchPromptIntent extends VoiceIntent {
  const SearchPromptIntent();
}

/// «Pon algo de» solo: SmartBuds pregunta «¿De quién?» y escucha el artista.
class ArtistPromptIntent extends VoiceIntent {
  const ArtistPromptIntent();
}

/// «Oye música»: SmartBuds responde «¿Sí?» y escucha una frase libre
/// («busca Ojalá de Ryan Castro», «pon algo de Karol G», o solo el nombre).
class WakeIntent extends VoiceIntent {
  const WakeIntent();
}

/// «Me gusta» / «Me encanta».
class LikeIntent extends VoiceIntent {
  const LikeIntent();
}

/// «No me gusta»: baja la puntuación y pasa a la siguiente.
class DislikeIntent extends VoiceIntent {
  const DislikeIntent();
}

/// «Pon algo que me guste» / «Pon mis favoritas».
class FavoriteIntent extends VoiceIntent {
  const FavoriteIntent();
}

/// «Pon algo nuevo»: canciones que aún no conoces, parecidas a tus gustos.
class DiscoverIntent extends VoiceIntent {
  const DiscoverIntent();
}

/// «Pon algo de Ryan Castro».
class ArtistIntent extends VoiceIntent {
  const ArtistIntent(this.artist);
  final String artist;
}

/// «Pon algo para entrenar», «algo tranquilo», «música para bailar».
class MoodIntent extends VoiceIntent {
  const MoodIntent(this.mood, this.query);

  /// Nombre del ambiente («entrenar», «tranquila»…), para la respuesta hablada.
  final String mood;

  /// Lo que se busca.
  final String query;
}

/// Apps de música conocidas: nombre hablado → (paquete Android, nombre visible).
const musicApps = <String, (String, String)>{
  'youtube music': ('com.google.android.apps.youtube.music', 'YouTube Music'),
  'youtube': ('com.google.android.apps.youtube.music', 'YouTube Music'),
  'apple music': ('com.apple.android.music', 'Apple Music'),
  'amazon music': ('com.amazon.mp3', 'Amazon Music'),
  'amazon': ('com.amazon.mp3', 'Amazon Music'),
  'deezer': ('deezer.android.app', 'Deezer'),
  'spotify': ('com.spotify.music', 'Spotify'),
};

/// Convierte lo que el usuario dijo en un comando universal.
/// Reglas locales, sin IA: así «Cambia» funciona sin internet y al instante.
class CommandParser {
  const CommandParser();

  /// Frases de varias palabras: se revisan antes que las palabras sueltas.
  static const _phrases = <String, MusicCommand>{
    'otra cancion': MusicCommand.next,
    'siguiente cancion': MusicCommand.next,
    'cancion anterior': MusicCommand.previous,
    'mas volumen': MusicCommand.volumeUp,
    'sube el volumen': MusicCommand.volumeUp,
    'menos volumen': MusicCommand.volumeDown,
    'baja el volumen': MusicCommand.volumeDown,
  };

  /// Palabras sueltas. Se evitan palabras muy comunes del español
  /// (como «para») para no disparar comandos en una conversación.
  static const _words = <String, MusicCommand>{
    'cambia': MusicCommand.next,
    'cambiala': MusicCommand.next,
    'cambiar': MusicCommand.next,
    'siguiente': MusicCommand.next,
    'pasa': MusicCommand.next,
    'salta': MusicCommand.next,
    'devuelve': MusicCommand.previous,
    'devuelvela': MusicCommand.previous,
    'anterior': MusicCommand.previous,
    'regresa': MusicCommand.previous,
    'pausa': MusicCommand.pause,
    'pausar': MusicCommand.pause,
    'detente': MusicCommand.pause,
    'stop': MusicCommand.pause,
    'continua': MusicCommand.play,
    'continuar': MusicCommand.play,
    'reanuda': MusicCommand.play,
    'play': MusicCommand.play,
    'reproduce': MusicCommand.play,
    'sube': MusicCommand.volumeUp,
    'baja': MusicCommand.volumeDown,
  };

  /// Frases que todavía no son comandos de reproducción (llegan con el
  /// Music Profile). Se reconocen para no confundirlas con otra orden.
  static const _reserved = ['no me gusta', 'me gusta'];

  MusicCommand? parse(String heard) {
    final text = normalize(heard);
    if (text.isEmpty) return null;
    final padded = ' $text ';
    for (final r in _reserved) {
      if (padded.contains(' $r ')) return null;
    }
    for (final entry in _phrases.entries) {
      if (padded.contains(' ${entry.key} ')) return entry.value;
    }
    for (final word in text.split(' ')) {
      final cmd = _words[word];
      if (cmd != null) return cmd;
    }
    return null;
  }

  static const _searchPrompts = {'busca', 'buscar', 'buscame', 'busca una cancion'};
  static const _likes = {
    'me gusta', 'me gusta esta', 'me gusta esta cancion', 'me encanta',
    'me encanta esta', 'me encanta esta cancion',
  };
  static const _dislikes = {
    'no me gusta', 'no me gusta esta', 'no me gusta esta cancion', 'quita esta',
  };
  static const _favorites = {
    'pon algo que me guste', 'algo que me guste', 'pon mis favoritas',
    'mis favoritas', 'pon mi musica', 'pon algo de lo mio',
  };

  static const _discover = {
    'pon algo nuevo', 'algo nuevo', 'descubre algo', 'descubreme algo',
    'sorprendeme', 'pon algo diferente', 'quiero algo nuevo',
  };

  /// Palabra clave del ambiente → (nombre, búsqueda).
  static const _moods = <String, (String, String)>{
    'entrenar': ('para entrenar', 'musica para entrenar'),
    'gym': ('para entrenar', 'musica para entrenar'),
    'ejercicio': ('para entrenar', 'musica para entrenar'),
    'tranquilo': ('tranquila', 'musica tranquila relajante'),
    'tranquila': ('tranquila', 'musica tranquila relajante'),
    'relajarme': ('tranquila', 'musica tranquila relajante'),
    'relajante': ('tranquila', 'musica tranquila relajante'),
    'fiesta': ('de fiesta', 'musica para bailar fiesta'),
    'bailar': ('de fiesta', 'musica para bailar fiesta'),
    'dormir': ('para dormir', 'musica para dormir'),
    'estudiar': ('para concentrarte', 'musica para estudiar concentracion'),
    'concentrarme': ('para concentrarte', 'musica para estudiar concentracion'),
    'trabajar': ('para concentrarte', 'musica para estudiar concentracion'),
    'romantico': ('romántica', 'canciones romanticas'),
    'romantica': ('romántica', 'canciones romanticas'),
    'alegre': ('alegre', 'musica alegre'),
    'feliz': ('alegre', 'musica alegre'),
    'triste': ('triste', 'canciones tristes'),
  };

  /// Palabra de activación. Debe existir en el vocabulario de Vosk en español.
  static const wakePhrases = {'oye musica', 'hola musica'};

  static const _artistPrompts = {
    'pon algo de', 'pon musica de', 'pon canciones de', 'quiero escuchar a',
  };

  /// Frases que el reconocedor sin internet (Vosk) puede devolver. Limitar el
  /// vocabulario a las órdenes hace que entienda mucho mejor con música de
  /// fondo, y cualquier otra cosa sale como «[unk]» (desconocido) y se ignora.
  /// Los nombres de canciones y artistas se escuchan aparte, después de
  /// «¿Qué canción?» / «¿De quién?», con el reconocedor preciso.
  static const voskGrammar = [
    'cambia', 'cambiar', 'siguiente', 'pasa', 'salta',
    'otra canción', 'siguiente canción',
    'devuelve', 'anterior', 'regresa', 'canción anterior',
    'pausa', 'pausar', 'detente',
    'continúa', 'continuar', 'reanuda', 'reproduce',
    'sube', 'baja', 'más volumen', 'menos volumen',
    'sube el volumen', 'baja el volumen',
    'busca', 'buscar', 'búscame', 'busca una canción',
    'me gusta', 'me gusta esta', 'me gusta esta canción', 'me encanta',
    'me encanta esta canción',
    'no me gusta', 'no me gusta esta', 'no me gusta esta canción', 'quita esta',
    'pon algo que me guste', 'algo que me guste', 'pon mis favoritas',
    'mis favoritas', 'pon mi música',
    'pon algo nuevo', 'algo nuevo', 'descubre algo',
    'pon algo diferente', 'quiero algo nuevo',
    'pon algo para entrenar', 'pon algo tranquilo', 'pon algo para relajarme',
    'pon algo de fiesta', 'pon algo para bailar', 'pon algo para dormir',
    'pon algo para estudiar', 'pon algo para trabajar', 'pon algo romántico',
    'pon algo alegre', 'pon algo triste',
    'pon algo de', 'pon música de',
    'oye música', 'hola música',
    '[unk]',
  ];

  static const _artistPrefixes = [
    'pon algo de ', 'pon musica de ', 'pon canciones de ', 'quiero escuchar a ',
    'pon lo de ', 'pon temas de ',
  ];

  /// Interpreta una frase completa dicha por voz. Solo cuenta si la frase
  /// entera es una orden (hablar o cantar con palabras sueltas no dispara nada).
  VoiceIntent? parseIntent(String heard) {
    final text = normalize(heard);
    if (text.isEmpty) return null;
    if (wakePhrases.contains(text)) return const WakeIntent();
    if (_searchPrompts.contains(text)) return const SearchPromptIntent();
    if (_dislikes.contains(text)) return const DislikeIntent();
    if (_likes.contains(text)) return const LikeIntent();
    if (_favorites.contains(text)) return const FavoriteIntent();
    if (_discover.contains(text)) return const DiscoverIntent();
    if (_artistPrompts.contains(text)) return const ArtistPromptIntent();
    if (text.startsWith('pon ') || text.startsWith('algo ') || text.startsWith('quiero ')) {
      for (final word in text.split(' ')) {
        final mood = _moods[word];
        if (mood != null) return MoodIntent(mood.$1, mood.$2);
      }
    }
    for (final prefix in _artistPrefixes) {
      if (text.startsWith(prefix) && text.length > prefix.length) {
        return ArtistIntent(text.substring(prefix.length).trim());
      }
    }
    final search = parseSearch(text);
    if (search != null) return SearchIntent(search);
    final cmd = parseExact(text);
    if (cmd != null) return CommandIntent(cmd);
    return null;
  }

  /// Frase libre dicha después de «Oye música»: una orden o pedido si lo es;
  /// si no, se toma como el nombre de una canción para buscar.
  VoiceIntent? parseFree(String heard) {
    final text = normalize(heard);
    if (text.isEmpty) return null;
    final intent = parseIntent(text);
    if (intent != null && intent is! WakeIntent) return intent;
    if (wakePhrases.contains(text)) return null;
    return SearchIntent(SearchRequest(heard.trim()));
  }

  /// Modo estricto para la voz: la frase completa debe ser una orden
  /// («cambia», «otra canción»), no una conversación que la contenga.
  MusicCommand? parseExact(String heard) {
    final text = normalize(heard);
    return _phrases[text] ?? _words[text];
  }

  /// «busca <algo> [en <app>]» → qué buscar y dónde; si no es búsqueda, null.
  SearchRequest? parseSearch(String heard) {
    final text = normalize(heard);
    const triggers = ['busca', 'buscar', 'buscame'];
    for (final t in triggers) {
      if (!text.startsWith('$t ')) continue;
      var query = text.substring(t.length).trim();
      for (final filler in ['la cancion ', 'cancion ', 'a ', 'el tema ']) {
        if (query.startsWith(filler)) query = query.substring(filler.length);
      }
      // «… en apple music»: la app va al final.
      String? pkg;
      String? name;
      for (final entry in musicApps.entries) {
        final suffix = ' en ${entry.key}';
        if (query.endsWith(suffix)) {
          query = query.substring(0, query.length - suffix.length).trim();
          (pkg, name) = entry.value;
          break;
        }
      }
      if (query.isEmpty) return null;
      return SearchRequest(query, appPackage: pkg, appName: name);
    }
    return null;
  }

  /// Minúsculas, sin tildes ni signos, espacios simples.
  static String normalize(String input) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      if (i >= 0) {
        buffer.write(to[i]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().trim().split(RegExp(r'\s+')).join(' ');
  }
}
