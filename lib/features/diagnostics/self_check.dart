/// Autodiagnóstico de SmartBuds: revisa voz, permisos, reproducción, conexión
/// y audífonos, explica qué ocurrió y cómo resolverlo. Es lógica pura (sin
/// Flutter) para poder probarla; los datos los junta [Assistant.selfCheck].
library;

enum CheckArea { voz, permisos, reproduccion, conexion, audifonos, bateria }

enum Severity { ok, warning, problem }

/// Arreglo que la app puede hacer (o abrir) con un toque.
enum FixAction { none, retryVoice, enableVoice, openAppSettings, openNotificationAccess, refreshHeadphones }

class Finding {
  const Finding(this.area, this.severity, this.title,
      {this.detail = '', this.fix = '', this.action = FixAction.none});
  final CheckArea area;
  final Severity severity;
  final String title;

  /// Qué ocurrió, en palabras simples.
  final String detail;

  /// Cómo resolverlo.
  final String fix;
  final FixAction action;

  bool get isOk => severity == Severity.ok;
}

typedef ErrorEntry = ({DateTime at, String kind, String message});

/// Foto del estado de la app en el momento de revisar.
class SelfCheckInput {
  const SelfCheckInput({
    required this.now,
    this.voiceSupported = true,
    this.micPermission,
    this.voiceEnabled = false,
    this.voiceFailed = false,
    this.voiceRecovering = false,
    this.voiceError,
    this.requireWakeWord = false,
    this.onlyMyVoice = false,
    this.lastRejectedVoice = false,
    this.ignoredVolumeFlips = 0,
    this.notificationAccess,
    this.playerApp,
    this.controlsLimited = false,
    this.online,
    this.errors = const [],
    this.headphones,
    this.unstableHeadphones = false,
    this.lowBattery = false,
  });

  final DateTime now;

  /// La voz existe en esta plataforma (Android / iPhone).
  final bool voiceSupported;
  final bool? micPermission;
  final bool voiceEnabled;
  final bool voiceFailed;
  final bool voiceRecovering;
  final String? voiceError;
  final bool requireWakeWord;
  final bool onlyMyVoice;
  final bool lastRejectedVoice;

  /// Órdenes de volumen ignoradas porque parecían conversación o canto.
  final int ignoredVolumeFlips;

  /// Acceso a notificaciones (Android). Null: no aplica (iPhone).
  final bool? notificationAccess;

  /// App de música abierta (o null).
  final String? playerApp;
  final bool controlsLimited;

  /// Hay internet. Null: no se pudo comprobar.
  final bool? online;
  final List<ErrorEntry> errors;
  final String? headphones;
  final bool unstableHeadphones;
  final bool lowBattery;
}

class SelfCheck {
  /// Solo cuentan los errores recientes (lo de ayer ya no explica lo de hoy).
  static const recent = Duration(minutes: 30);

  static List<Finding> run(SelfCheckInput i) {
    final out = <Finding>[];
    final errs = i.errors.where((e) => i.now.difference(e.at) <= recent).toList();

    // ---------------------------------------------------------------- Voz
    final voz = <Finding>[];
    if (!i.voiceSupported) {
      voz.add(const Finding(CheckArea.voz, Severity.warning, 'La voz de Jarvis no está en esta versión',
          detail: 'La escucha continua funciona en la app de Android y iPhone.',
          fix: 'En la página web toca el micrófono para hablar.'));
    } else if (i.micPermission == false) {
      voz.add(const Finding(CheckArea.voz, Severity.problem, 'Falta el permiso de micrófono',
          detail: 'El teléfono no deja que SmartBuds use el micrófono, así que Jarvis no puede oírte.',
          fix: 'Abre los ajustes de SmartBuds y activa «Micrófono» (en iPhone también «Reconocimiento de voz»).',
          action: FixAction.openAppSettings));
    } else if (i.voiceFailed) {
      voz.add(Finding(CheckArea.voz, Severity.problem, 'Jarvis dejó de escuchar',
          detail: _explainVoice(i.voiceError) ??
              'El micrófono se cerró y no se pudo reabrir solo después de varios intentos.',
          fix: 'Toca «Reintentar». Si vuelve a pasar, cierra otras apps que usen el micrófono (llamadas, grabadora, otro asistente).',
          action: FixAction.retryVoice));
    } else if (!i.voiceEnabled) {
      voz.add(const Finding(CheckArea.voz, Severity.warning, 'Jarvis está apagado',
          detail: 'La escucha continua no está activa.',
          fix: 'Toca el micrófono grande o «Encender».', action: FixAction.enableVoice));
    } else if (i.voiceRecovering) {
      voz.add(const Finding(CheckArea.voz, Severity.warning, 'Reabriendo el micrófono',
          detail: 'El sistema cerró el micrófono (otra app, una llamada o un cambio de audífonos). Jarvis lo está reabriendo.',
          fix: 'Espera unos segundos. Si no vuelve, toca «Reintentar».'));
    }
    if (i.voiceSupported && i.voiceEnabled && i.requireWakeWord) {
      voz.add(const Finding(CheckArea.voz, Severity.warning, 'Solo obedece después de «Oye música»',
          detail: 'Está activada la palabra de activación: las órdenes sueltas se ignoran.',
          fix: 'Di «Oye música» antes de la orden, o apágala en Asistente → Voz y escucha.'));
    }
    if (i.voiceSupported && i.onlyMyVoice && i.lastRejectedVoice) {
      voz.add(const Finding(CheckArea.voz, Severity.warning, '«Solo mi voz» ignoró la última frase',
          detail: 'Jarvis no reconoció la voz como tuya (ruido, distancia o música fuerte).',
          fix: 'Vuelve a entrenar tu voz o baja la exigencia en Asistente → Voz y escucha.'));
    }
    if (i.ignoredVolumeFlips > 0) {
      voz.add(Finding(CheckArea.voz, Severity.warning,
          'Ignoré ${i.ignoredVolumeFlips} ${i.ignoredVolumeFlips == 1 ? 'orden' : 'órdenes'} de volumen que parecía${i.ignoredVolumeFlips == 1 ? '' : 'n'} conversación',
          detail: 'Llegaron «sube» y «baja» seguidos mientras hablabas o cantabas; así la música no sube y baja sola.',
          fix: 'Para cambiar el volumen di la frase completa: «sube el volumen». «Solo mi voz» también ayuda.'));
    }
    final voiceErrs = errs.where((e) => e.kind == 'voz').toList();
    if (voiceErrs.length >= 3 && !i.voiceFailed) {
      voz.add(Finding(CheckArea.voz, Severity.warning, 'La voz falló ${voiceErrs.length} veces hace poco',
          detail: _explainVoice(voiceErrs.first.message) ?? voiceErrs.first.message,
          fix: 'Jarvis se recupera solo; si notas que no responde, toca «Reintentar».'));
    }
    out.addAll(voz.isEmpty
        ? [const Finding(CheckArea.voz, Severity.ok, 'Jarvis te está escuchando')]
        : voz);

    // ----------------------------------------------------------- Permisos
    if (i.notificationAccess == false) {
      out.add(const Finding(CheckArea.permisos, Severity.problem, 'Falta el acceso a notificaciones',
          detail: 'Sin ese permiso SmartBuds no ve qué suena ni controla tus apps de música. No lee tus mensajes.',
          fix: 'Toca «Dar permiso» y activa SmartBuds.', action: FixAction.openNotificationAccess));
    } else {
      out.add(const Finding(CheckArea.permisos, Severity.ok, 'Permisos en orden'));
    }

    // -------------------------------------------------------- Reproducción
    final rep = <Finding>[];
    final cmdErrs = errs.where((e) => e.kind.startsWith('comando_')).toList();
    if (i.playerApp == null) {
      rep.add(const Finding(CheckArea.reproduccion, Severity.warning, 'No hay app de música abierta',
          detail: 'Las órdenes no tienen a quién llegar.',
          fix: 'Abre Spotify, YouTube Music u otra app y pon una canción (aunque sea en pausa).'));
    } else if (i.controlsLimited) {
      rep.add(Finding(CheckArea.reproduccion, Severity.warning, '${i.playerApp} limita algunos controles',
          detail: 'Puede que «siguiente» o el volumen no funcionen siempre con esa app.',
          fix: 'Prueba con YouTube Music o Spotify.'));
    }
    if (cmdErrs.isNotEmpty) {
      final what = _commandName(cmdErrs.first.kind);
      rep.add(Finding(CheckArea.reproduccion, Severity.problem,
          'Tu app de música no obedeció${what == null ? '' : ' «$what»'}',
          detail: cmdErrs.length > 1
              ? 'Pasó ${cmdErrs.length} veces en la última media hora.'
              : 'La app no respondió a la orden.',
          fix: 'Abre la app de música, toca reproducir una vez y prueba otra vez. Si sigue, ciérrala y ábrela.'));
    }
    if (errs.any((e) => e.kind == 'busqueda')) {
      rep.add(Finding(CheckArea.reproduccion, Severity.warning, 'Una búsqueda falló',
          detail: i.online == false ? 'No hay internet.' : 'El servicio de búsqueda no respondió.',
          fix: 'Prueba de nuevo en un momento o di el nombre de otra forma.'));
    }
    out.addAll(rep.isEmpty
        ? [Finding(CheckArea.reproduccion, Severity.ok, 'Reproducción en orden: ${i.playerApp}')]
        : rep);

    // ----------------------------------------------------------- Conexión
    if (i.online == false) {
      out.add(const Finding(CheckArea.conexion, Severity.problem, 'Sin internet',
          detail: 'Sin internet siguen funcionando los controles y la voz (Android). '
              'No funcionan: búsquedas, «cuéntame de…», descubrimientos ni la copia en la nube.',
          fix: 'Revisa el Wi-Fi o los datos móviles.'));
    } else if (i.online == true) {
      out.add(const Finding(CheckArea.conexion, Severity.ok, 'Conectado a internet'));
    }

    // ---------------------------------------------------------- Audífonos
    if (i.unstableHeadphones) {
      out.add(const Finding(CheckArea.audifonos, Severity.problem, 'Los audífonos se desconectan seguido',
          detail: 'Se desconectaron 3 o más veces en 15 minutos.',
          fix: 'Acércalos al teléfono, cárgalos o vuelve a emparejarlos.'));
    } else if (i.headphones == null) {
      out.add(const Finding(CheckArea.audifonos, Severity.warning, 'No hay audífonos conectados',
          detail: 'La música sale por el altavoz y los toques de audífono no funcionan.',
          fix: 'Revisa que estén encendidos y emparejados.', action: FixAction.refreshHeadphones));
    } else {
      out.add(Finding(CheckArea.audifonos, Severity.ok, 'Audífonos conectados: ${i.headphones}'));
    }

    // ------------------------------------------------------------ Batería
    if (i.lowBattery) {
      out.add(const Finding(CheckArea.bateria, Severity.warning, 'Batería baja',
          detail: 'Jarvis responde más corto y los efectos visuales se apagan para ahorrar.',
          fix: 'Conecta el cargador; todo vuelve a la normalidad solo.'));
    }
    return out;
  }

  /// Resumen para decirlo en voz alta (máximo tres cosas).
  static String spokenSummary(List<Finding> findings) {
    final problems = findings.where((f) => f.severity == Severity.problem).toList();
    final warnings = findings.where((f) => f.severity == Severity.warning).toList();
    if (problems.isEmpty && warnings.isEmpty) return 'Revisé todo y funciona bien.';
    final top = [...problems, ...warnings].take(3).map((f) => f.title.toLowerCase()).join('; ');
    final n = problems.isNotEmpty ? problems.length : warnings.length;
    final kind = problems.isNotEmpty
        ? (n == 1 ? 'un problema' : '$n problemas')
        : (n == 1 ? 'algo por revisar' : '$n cosas por revisar');
    return 'Encontré $kind: $top. En Autodiagnóstico te digo cómo arreglarlo.';
  }

  /// Traduce mensajes técnicos de voz a palabras simples (null si no se conoce).
  static String? _explainVoice(String? message) {
    final m = (message ?? '').toLowerCase();
    if (m.isEmpty) return null;
    if (m.contains('permis')) return 'Falta un permiso de micrófono o de reconocimiento de voz.';
    if (m.contains('modelo') || m.contains('model')) {
      return 'No se pudo cargar el reconocimiento de voz del teléfono. Reinstalar la app suele resolverlo.';
    }
    if (m.contains('ocupado') || m.contains('busy') || m.contains('otra app') || m.contains('in use')) {
      return 'Otra app está usando el micrófono.';
    }
    if (m.contains('red') || m.contains('network') || m.contains('internet')) {
      return 'El reconocimiento de voz necesitó internet y no lo tuvo.';
    }
    if (m.contains('dejó de escuchar') || m.contains('reintentos')) {
      return 'El micrófono se cerró y no se pudo reabrir solo después de varios intentos.';
    }
    return null;
  }

  static String? _commandName(String kind) => switch (kind.replaceFirst('comando_', '')) {
        'next' => 'siguiente',
        'previous' => 'anterior',
        'pause' => 'pausa',
        'play' => 'continuar',
        'togglePlayPause' => 'pausa',
        'volumeUp' => 'subir volumen',
        'volumeDown' => 'bajar volumen',
        _ => null,
      };
}
