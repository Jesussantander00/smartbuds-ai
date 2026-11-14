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

/// «¿Qué suena?»: SmartBuds dice el nombre de la canción.
class NowPlayingIntent extends VoiceIntent {
  const NowPlayingIntent();
}

/// «Repite» / «Otra vez»: la canción actual desde el principio.
class RestartIntent extends VoiceIntent {
  const RestartIntent();
}

/// «Adelanta» / «Atrasa»: salta [seconds] (negativo = atrás).
class SeekIntent extends VoiceIntent {
  const SeekIntent(this.seconds);
  final int seconds;
}

/// «Apaga en 20 minutos». [minutes] = 0 cancela el temporizador.
class SleepIntent extends VoiceIntent {
  const SleepIntent(this.minutes);
  final int minutes;
}

/// «Deshacer»: vuelve a la canción anterior en el punto donde iba.
class UndoIntent extends VoiceIntent {
  const UndoIntent();
}

/// «Comparte esta»: prepara el enlace de la canción para enviarlo.
class ShareIntent extends VoiceIntent {
  const ShareIntent();
}

/// «Pon mi radio»: música sin parar, mezclando favoritas y descubrimientos.
class RadioIntent extends VoiceIntent {
  const RadioIntent({this.on = true});
  final bool on;
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

/// «Volumen al cincuenta», «pon el volumen en 30», «volumen al máximo».
class VolumeIntent extends VoiceIntent {
  const VolumeIntent(this.percent);
  final int percent;
}

/// «Después pon Ojalá»: la pone cuando termine o cambie la actual.
/// [query] null = SmartBuds pregunta «¿Qué pongo después?».
class QueueIntent extends VoiceIntent {
  const QueueIntent([this.query]);
  final String? query;
}

/// «La que dice "baby no me llames"»: busca por un pedazo de la letra.
/// [words] null = SmartBuds pregunta «¿Qué dice la letra?».
class LyricsIntent extends VoiceIntent {
  const LyricsIntent([this.words]);
  final String? words;
}

/// «Nunca más esta» / «Nunca más este artista»: no vuelve a sonar.
class BlockIntent extends VoiceIntent {
  const BlockIntent({this.artist = false});
  final bool artist;
}

/// «Cambia y sube»: varias órdenes seguidas en una frase.
class MultiIntent extends VoiceIntent {
  const MultiIntent(this.parts);
  final List<VoiceIntent> parts;
}

/// «Pon favoritas olvidadas»: canciones que te encantaban y hace rato no suenan.
class ForgottenIntent extends VoiceIntent {
  const ForgottenIntent();
}

/// «Comparte mi semana»: tu resumen musical para enviar.
class ShareWeekIntent extends VoiceIntent {
  const ShareWeekIntent();
}

/// «Pon algo parecido»: una canción de un artista parecido al que suena.
class SimilarIntent extends VoiceIntent {
  const SimilarIntent();
}

/// «¿Por qué me gusta esta?»: SmartBuds explica lo que sabe de ella.
class WhyIntent extends VoiceIntent {
  const WhyIntent();
}

/// «Cuéntame de Feid» / «¿Quién es este artista?»: lo que se sabe de él,
/// con fuente (Wikipedia, Deezer) y sus colaboraciones en tu música.
/// [artist] null = el que está sonando.
class ArtistInfoIntent extends VoiceIntent {
  const ArtistInfoIntent([this.artist]);
  final String? artist;
}

/// «¿Cómo han cambiado mis gustos este año?»: tu evolución musical.
class TasteEvolutionIntent extends VoiceIntent {
  const TasteEvolutionIntent();
}

/// «Pon media hora de música»: una lista de tus canciones para ese tiempo.
class DurationIntent extends VoiceIntent {
  const DurationIntent(this.minutes);
  final int minutes;
}

/// «Modo estudio / viaje / diario»: aplica un perfil de uso.
class UsageProfileIntent extends VoiceIntent {
  const UsageProfileIntent(this.profile);
  final String profile;
}

/// «Sube la energía poco a poco»: de tranquila a fiesta, canción a canción.
class EnergyRampIntent extends VoiceIntent {
  const EnergyRampIntent();
}

/// «Modo privado» / «Sal del modo privado»: dejar de aprender lo que suena.
class PrivateModeIntent extends VoiceIntent {
  const PrivateModeIntent(this.on);
  final bool on;
}

/// «Modo carro» / «Sal del modo carro»: pantalla grande y simple para el auto.
class CarModeIntent extends VoiceIntent {
  const CarModeIntent(this.on);
  final bool on;
}

/// Una automatización o comando personalizado tuyo («vamos al gimnasio»).
class MacroIntent extends VoiceIntent {
  const MacroIntent(this.id, this.name);
  final String id;
  final String name;
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
    // Más formas de decirlo (reconocimiento de ambiente).
    'relajado': ('tranquila', 'musica tranquila relajante'),
    'relajada': ('tranquila', 'musica tranquila relajante'),
    'calmado': ('tranquila', 'musica tranquila relajante'),
    'calmada': ('tranquila', 'musica tranquila relajante'),
    'chill': ('tranquila', 'musica chill'),
    'cansado': ('tranquila', 'musica tranquila relajante'),
    'cansada': ('tranquila', 'musica tranquila relajante'),
    'nostalgico': ('nostálgica', 'clasicos que marcaron epoca'),
    'nostalgica': ('nostálgica', 'clasicos que marcaron epoca'),
    'nostalgia': ('nostálgica', 'clasicos que marcaron epoca'),
    'recuerdos': ('nostálgica', 'clasicos que marcaron epoca'),
    'energia': ('con energía', 'musica con energia motivacion'),
    'energetico': ('con energía', 'musica con energia motivacion'),
    'energetica': ('con energía', 'musica con energia motivacion'),
    'motivado': ('con energía', 'musica con energia motivacion'),
    'motivada': ('con energía', 'musica con energia motivacion'),
    'animado': ('alegre', 'musica alegre'),
    'animada': ('alegre', 'musica alegre'),
    'contento': ('alegre', 'musica alegre'),
    'contenta': ('alegre', 'musica alegre'),
    'enamorado': ('romántica', 'canciones romanticas'),
    'enamorada': ('romántica', 'canciones romanticas'),
    'despecho': ('de despecho', 'canciones de despecho'),
    'melancolico': ('triste', 'canciones tristes'),
    'melancolica': ('triste', 'canciones tristes'),
  };

  /// «estoy nostálgico», «me siento con energía», «ando relajado»…
  static const _feelingPrefixes = ['estoy ', 'me siento ', 'ando ', 'tengo ganas de algo ', 'quiero algo '];

  /// Reconoce el ambiente en una frase libre, o null.
  static (String, String)? detectMood(String heard) {
    final text = normalize(heard);
    for (final word in text.split(' ')) {
      final m = _moods[word];
      if (m != null) return m;
    }
    return null;
  }

  /// Palabra de activación. Debe existir en el vocabulario de Vosk en español.
  static const wakePhrases = {'oye musica', 'hola musica'};

  /// Palabra de activación elegida por la persona (ajustes), ya normalizada.
  static Set<String> customWakePhrases = {};

  static const _nowPlaying = {
    'que suena', 'que esta sonando', 'que cancion es esta', 'como se llama esta cancion',
    'que cancion es', 'como se llama',
  };
  static const _restart = {'repite', 'repitela', 'otra vez', 'desde el principio', 'de nuevo'};
  static const _seek = {
    'adelanta': 30, 'adelantala': 30, 'adelanta un poco': 30,
    'atrasa': -30, 'atrasala': -30, 'atrasa un poco': -30,
  };
  static const _undo = {'deshacer', 'deshaz', 'me equivoque', 'deshaz eso'};
  static const _share = {'comparte esta', 'comparte la cancion', 'compartir', 'comparte esta cancion'};
  static const _radioOn = {'pon mi radio', 'modo radio', 'radio', 'pon la radio'};
  static const _radioOff = {'quita la radio', 'apaga la radio'};
  static const _sleepCancel = {'cancela el temporizador', 'no apagues', 'cancela el apagado'};

  /// Números dichos en palabras (para «apaga en veinte minutos»).
  static const sleepNumbers = {
    'cinco': 5, 'diez': 10, 'quince': 15, 'veinte': 20, 'treinta': 30,
    'cuarenta y cinco': 45, 'sesenta': 60,
  };

  static const _queuePrompts = {'despues pon', 'luego pon', 'pon despues', 'ponla despues'};
  static const _lyricsPrompts = {'la que dice', 'busca la que dice', 'la cancion que dice'};
  static const _blockTrack = {
    'nunca mas esta', 'no quiero escuchar mas esta', 'nunca mas esta cancion',
    'bloquea esta cancion', 'no me la pongas mas',
  };
  static const _blockArtist = {
    'nunca mas este artista', 'bloquea este artista', 'no quiero escuchar mas este artista',
  };
  static const _forgotten = {
    'pon favoritas olvidadas', 'favoritas olvidadas', 'mis favoritas olvidadas',
    'algo que no escucho hace rato', 'pon algo que no escucho hace rato',
  };
  static const _similar = {
    'pon algo parecido', 'algo parecido', 'pon una parecida', 'algo parecido a esta',
    'pon algo parecido a esta', 'parecidas a esta',
  };
  static const _why = {
    'por que esta', 'por que me gusta esta', 'por que me gusta', 'por que pusiste esta',
    'por que me gusta esta cancion',
  };
  static const _profiles = {
    'modo estudio': 'estudio', 'modo concentracion': 'estudio', 'modo viaje': 'viaje',
    'modo diario': 'diario', 'modo normal': 'diario',
  };
  static const _evolution = {
    'como han cambiado mis gustos',
    'como han cambiado mis gustos este ano',
    'como cambiaron mis gustos',
    'como ha cambiado mi musica',
    'como ha cambiado mi gusto musical',
    'mi evolucion musical',
    'cual es mi evolucion musical',
  };

  static const _aboutCurrent = {
    'cuentame de este artista',
    'cuentame del artista',
    'hablame de este artista',
    'hablame del artista',
    'quien es este artista',
    'quien es el artista',
    'que sabes de este artista',
  };
  static const _aboutPrefixes = [
    'cuentame de ',
    'cuentame sobre ',
    'hablame de ',
    'hablame sobre ',
    'que sabes de ',
    'quien es ',
  ];

  static const _carOn = {
    'modo carro',
    'modo auto',
    'modo automovil',
    'modo coche',
    'modo conduccion',
    'voy a manejar',
    'voy manejando',
  };
  static const _carOff = {
    'sal del modo carro',
    'quita el modo carro',
    'sal del modo auto',
    'sal del modo automovil',
    'ya llegue',
  };

  static const _energy = {
    'sube la energia poco a poco', 'sube la energia', 'de tranquila a fiesta', 'calentamiento',
  };
  static const _shareWeek = {'comparte mi semana', 'comparte mi resumen'};

  /// Números dichos en palabras para el volumen exacto.
  static const volumeNumbers = {
    'cero': 0, 'diez': 10, 'veinte': 20, 'treinta': 30, 'cuarenta': 40,
    'cincuenta': 50, 'sesenta': 60, 'setenta': 70, 'ochenta': 80,
    'noventa': 90, 'cien': 100, 'la mitad': 50, 'medio': 50,
    'maximo': 100, 'minimo': 10, 'tope': 100,
  };

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
    'qué suena', 'qué está sonando', 'qué canción es esta', 'cómo se llama esta canción',
    'repite', 'otra vez', 'desde el principio', 'de nuevo',
    'adelanta', 'atrasa', 'adelanta un poco', 'atrasa un poco',
    'deshacer', 'deshaz', 'me equivoqué',
    'comparte esta', 'comparte la canción',
    'pon mi radio', 'modo radio', 'quita la radio',
    'cancela el temporizador', 'no apagues',
    'después pon', 'luego pon', 'pon después',
    'la que dice', 'la canción que dice',
    'nunca más esta', 'no quiero escuchar más esta', 'nunca más esta canción',
    'nunca más este artista', 'bloquea este artista',
    'pon favoritas olvidadas', 'mis favoritas olvidadas', 'algo que no escucho hace rato',
    'comparte mi semana',
    'modo estudio', 'modo viaje', 'modo diario', 'modo normal',
    'modo privado', 'modo incógnito', 'sal del modo privado', 'quita el modo privado',
    'sube la energía poco a poco', 'sube la energía',
    'pon media hora de música', 'pon una hora de música', 'pon quince minutos de música',
    'pon treinta minutos de música', 'pon diez minutos de música',
    'pon algo parecido', 'algo parecido a esta', 'pon una parecida',
    'por qué esta', 'por qué me gusta esta', 'por qué pusiste esta',
    'volumen al máximo', 'volumen al mínimo', 'volumen a la mitad',
    'volumen al diez', 'volumen al veinte', 'volumen al treinta', 'volumen al cuarenta',
    'volumen al cincuenta', 'volumen al sesenta', 'volumen al setenta',
    'volumen al ochenta', 'volumen al noventa', 'volumen al cien',
    'pon el volumen al máximo', 'pon el volumen al cincuenta',
    'cambia y sube', 'cambia y baja', 'pausa y baja', 'siguiente y sube',
    'cambia y me gusta', 'me gusta y cambia', 'sube y cambia', 'baja y cambia',
    'estoy relajado', 'estoy cansado', 'estoy triste', 'estoy feliz', 'estoy nostálgico',
    'me siento nostálgico', 'me siento con energía', 'estoy enamorado', 'pon algo nostálgico',
    'pon algo con energía', 'pon algo relajado',
    'apaga en cinco minutos', 'apaga en diez minutos', 'apaga en quince minutos',
    'apaga en veinte minutos', 'apaga en treinta minutos',
    'apaga en cuarenta y cinco minutos', 'apaga en sesenta minutos', 'apaga en una hora',
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
    if (wakePhrases.contains(text) || customWakePhrases.contains(text)) {
      return const WakeIntent();
    }
    final multi = _parseMulti(text);
    if (multi != null) return multi;
    if (_nowPlaying.contains(text)) return const NowPlayingIntent();
    final volume = parseVolume(text);
    if (volume != null) return VolumeIntent(volume);
    if (_queuePrompts.contains(text)) return const QueueIntent();
    if (_lyricsPrompts.contains(text)) return const LyricsIntent();
    if (_blockTrack.contains(text)) return const BlockIntent();
    if (_blockArtist.contains(text)) return const BlockIntent(artist: true);
    if (_forgotten.contains(text)) return const ForgottenIntent();
    if (_shareWeek.contains(text)) return const ShareWeekIntent();
    if (_similar.contains(text)) return const SimilarIntent();
    if (text == 'modo privado' || text == 'modo incognito') return const PrivateModeIntent(true);
    if (text == 'sal del modo privado' || text == 'quita el modo privado') {
      return const PrivateModeIntent(false);
    }
    if (_carOn.contains(text)) return const CarModeIntent(true);
    if (_carOff.contains(text)) return const CarModeIntent(false);
    if (_evolution.contains(text)) return const TasteEvolutionIntent();
    if (_aboutCurrent.contains(text)) return const ArtistInfoIntent();
    for (final p in _aboutPrefixes) {
      if (text.startsWith(p)) {
        final who = text.substring(p.length).trim();
        if (who.isNotEmpty) return ArtistInfoIntent(who);
      }
    }
    final prof = _profiles[text];
    if (prof != null) return UsageProfileIntent(prof);
    if (_energy.contains(text)) return const EnergyRampIntent();
    final dur = parseDuration(text);
    if (dur != null) return DurationIntent(dur);
    if (_why.contains(text)) return const WhyIntent();
    for (final p in const ['despues pon ', 'luego pon ', 'en cola pon ', 'pon despues ']) {
      if (text.startsWith(p) && text.length > p.length + 2) {
        return QueueIntent(text.substring(p.length).trim());
      }
    }
    for (final p in const ['la que dice ', 'busca la que dice ', 'la cancion que dice ']) {
      if (text.startsWith(p) && text.length > p.length + 2) {
        return LyricsIntent(text.substring(p.length).trim());
      }
    }
    if (_restart.contains(text)) return const RestartIntent();
    final seek = _seek[text];
    if (seek != null) return SeekIntent(seek);
    if (_undo.contains(text)) return const UndoIntent();
    if (_share.contains(text)) return const ShareIntent();
    if (_radioOn.contains(text)) return const RadioIntent();
    if (_radioOff.contains(text)) return const RadioIntent(on: false);
    if (_sleepCancel.contains(text)) return const SleepIntent(0);
    final sleep = parseSleep(text);
    if (sleep != null) return SleepIntent(sleep);
    if (_searchPrompts.contains(text)) return const SearchPromptIntent();
    if (_dislikes.contains(text)) return const DislikeIntent();
    if (_likes.contains(text)) return const LikeIntent();
    if (_favorites.contains(text)) return const FavoriteIntent();
    if (_discover.contains(text)) return const DiscoverIntent();
    if (_artistPrompts.contains(text)) return const ArtistPromptIntent();
    if (_feelingPrefixes.any(text.startsWith)) {
      final m = detectMood(text);
      if (m != null) return MoodIntent(m.$1, m.$2);
    }
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

  /// «cambia y sube» → [CommandIntent(next), CommandIntent(volumeUp)].
  /// Solo si TODAS las partes son órdenes cortas (no rompe «busca X y Y»).
  MultiIntent? _parseMulti(String text) {
    if (!text.contains(' y ')) return null;
    final parts = text.split(' y ');
    if (parts.length < 2 || parts.length > 3) return null;
    final out = <VoiceIntent>[];
    for (final part in parts) {
      final p = part.trim();
      final cmd = parseExact(p);
      if (cmd != null) {
        out.add(CommandIntent(cmd));
        continue;
      }
      if (_likes.contains(p)) {
        out.add(const LikeIntent());
        continue;
      }
      if (_dislikes.contains(p)) {
        out.add(const DislikeIntent());
        continue;
      }
      final v = parseVolume(p);
      if (v != null) {
        out.add(VolumeIntent(v));
        continue;
      }
      return null;
    }
    return MultiIntent(out);
  }

  /// «volumen al cincuenta», «pon el volumen en 30», «volumen al máximo» → 0–100.
  int? parseVolume(String heard) {
    final text = normalize(heard);
    final m = RegExp(r'^(pon |sube |baja )?(el )?volumen (al|a|en) (.+?)( por ciento)?$')
        .firstMatch(text);
    if (m == null) return null;
    var what = m.group(4)!.trim();
    if (what.startsWith('el ')) what = what.substring(3);
    final n = int.tryParse(what) ?? volumeNumbers[what];
    if (n == null || n < 0 || n > 100) return null;
    return n;
  }

  /// «apaga en veinte minutos», «apaga en 20 minutos», «apaga en una hora».
  int? parseSleep(String heard) {
    final text = normalize(heard);
    final m = RegExp(r'^(apaga|apagar|duerme|apagate) en (.+?)( minutos?)?$').firstMatch(text);
    if (m == null) return null;
    final what = m.group(2)!;
    if (what == 'una hora' || what == 'una hora mas') return 60;
    final n = int.tryParse(what) ?? sleepNumbers[what];
    if (n == null || n <= 0 || n > 180) return null;
    return n;
  }

  /// Escucha abierta (no hay música sonando): además de las órdenes, se
  /// aceptan pedidos que empiezan con «pon …», «reproduce …» o «quiero
  /// escuchar …». Cualquier otra conversación se ignora.
  VoiceIntent? parseOpen(String heard) {
    final intent = parseIntent(heard);
    if (intent != null) return intent;
    final text = normalize(heard);
    final m = RegExp(r'^(pon|ponme|reproduce|quiero escuchar|toca) (la cancion |a |el tema )?(.+)$')
        .firstMatch(text);
    if (m == null) return null;
    final query = m.group(3)!.trim();
    if (query.split(' ').length < 2 && query.length < 4) return null; // muy corto
    return SearchIntent(SearchRequest(refineQuery(query)));
  }

  /// Frase libre dicha después de «Oye música»: una orden o pedido si lo es;
  /// si no, se toma como el nombre de una canción para buscar.
  VoiceIntent? parseFree(String heard) {
    final text = normalize(heard);
    if (text.isEmpty) return null;
    final intent = parseIntent(text);
    if (intent != null && intent is! WakeIntent) return intent;
    if (wakePhrases.contains(text)) return null;
    return SearchIntent(SearchRequest(refineQuery(heard.trim())));
  }

  /// Modo estricto para la voz: la frase completa debe ser una orden
  /// («cambia», «otra canción»), no una conversación que la contenga.
  MusicCommand? parseExact(String heard) {
    final text = normalize(heard);
    return _phrases[text] ?? _words[text];
  }

  /// «pon media hora de música», «treinta minutos de música» → minutos.
  int? parseDuration(String heard) {
    final text = normalize(heard);
    final m = RegExp(r'^(pon |ponme |quiero )?(una lista de )?(.+?) de (musica|canciones)$').firstMatch(text);
    if (m == null) return null;
    final what = m.group(3)!;
    if (what == 'media hora') return 30;
    if (what == 'una hora') return 60;
    if (what == 'hora y media') return 90;
    if (what == 'un cuarto de hora') return 15;
    final mm = RegExp(r'^(.+?) minutos$').firstMatch(what);
    if (mm == null) return null;
    final w = mm.group(1)!;
    final n = int.tryParse(w) ?? sleepNumbers[w];
    if (n == null || n < 5 || n > 180) return null;
    return n;
  }

  /// Mejora lo que se va a buscar:
  /// - época: «música de los ochenta» → «éxitos de los 80»
  /// - versiones: «versión acústica de Tusa» → «Tusa acústico»
  /// - descripción: «una canción tranquila con guitarra» → «canción tranquila guitarra»
  static String refineQuery(String query) {
    var q = normalize(query);
    const eras = {
      'sesenta': '60', 'setenta': '70', 'ochenta': '80', 'noventa': '90',
      'dos mil': '2000', '2000s': '2000', 'dosmil': '2000',
      '60': '60', '70': '70', '80': '80', '90': '90', '2000': '2000', '2010': '2010',
    };
    final era = RegExp(r'^(musica |canciones |algo |exitos |exitos )?(.*?)\s*de los (anos )?(\w+( mil)?)$')
        .firstMatch(q);
    if (era != null && eras.containsKey(era.group(4))) {
      final genre = era.group(2)!.trim();
      final decade = eras[era.group(4)]!;
      return genre.isEmpty ? 'exitos de los $decade' : '$genre de los $decade exitos';
    }
    const versions = {
      'acustica': 'acustico', 'acustico': 'acustico', 'en vivo': 'en vivo',
      'remix': 'remix', 'original': 'official audio', 'oficial': 'official audio',
      'lenta': 'slowed', 'instrumental': 'instrumental', 'karaoke': 'karaoke',
    };
    final ver = RegExp(r'^(la )?(version )?(acustica|acustico|en vivo|remix|original|oficial|lenta|instrumental|karaoke) de (.+)$')
        .firstMatch(q);
    if (ver != null) return '${ver.group(4)} ${versions[ver.group(3)]}';
    final desc = RegExp(r'^(una |alguna )?(cancion|musica|algo) (.+)$').firstMatch(q);
    if (desc != null && desc.group(3)!.split(' ').length >= 2) {
      final words = desc
          .group(3)!
          .split(' ')
          .where((w) => !const {'con', 'que', 'tenga', 'de', 'y', 'una', 'un', 'para'}.contains(w))
          .join(' ');
      return '${desc.group(2) == 'musica' ? 'musica' : 'cancion'} $words';
    }
    return query.trim();
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
      return SearchRequest(refineQuery(query), appPackage: pkg, appName: name);
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
