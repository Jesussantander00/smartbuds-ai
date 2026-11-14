/// Novedades de SmartBuds, de la más reciente a la más antigua.
/// Subir [latestChangelog] cuando se agrega una entrada.
const latestChangelog = 26;

const changelog = <({int version, String title, List<String> items})>[
  (
    version: 26,
    title: 'Audio y audífonos',
    items: [
      'Ecualizador inteligente: perfiles por audífono y por tipo de música, con bandas manuales.',
      'El analizador marca qué dato es real y cuál es estimado, y muestra la calidad de cada plataforma.',
      'Transiciones: baja el volumen al final de cada canción y lo sube en la siguiente (Android).',
      'Dispositivos → Diagnóstico de audífonos: cortes, duración de cada conexión y qué hacer.',
    ],
  ),
  (
    version: 25,
    title: 'Jarvis más inteligente',
    items: [
      'Encadena órdenes: «pon algo para entrenar y luego volumen al 80»; al final te confirma todo junto.',
      'En Inicio, Jarvis muestra lo que te escuchó, lo que entendió y acciones rápidas.',
      'Asistente → Voz personalizada: estilo breve, normal, charla o técnico, velocidad y tono.',
      'Indicador «Escuchando» en todas las secciones; di «deja de escuchar» para parar.',
    ],
  ),
  (
    version: 24,
    title: 'Tu memoria musical',
    items: [
      'Pregunta «¿cómo han cambiado mis gustos este año?» o abre Mi música → Tu evolución.',
      'SmartBuds nota el ambiente de lo que suena y sigue en esa línea.',
      'Radar con artistas emergentes: separa los datos reales de las predicciones.',
    ],
  ),
  (
    version: 23,
    title: 'Conocimiento musical y extensiones',
    items: [
      'Di «cuéntame de Feid» o toca un artista en Mi música: resumen con fuente, parecidos y sus colaboraciones en tu música.',
      'Privacidad y ayuda → Extensiones: enciende o apaga Amigos, Automatizaciones, Modo carro y más.',
      'SmartBuds Premium: próximamente. Lo básico siempre será gratis.',
    ],
  ),
  (
    version: 22,
    title: 'Estadísticas y copia de seguridad',
    items: [
      'Mi música → Estadísticas avanzadas: tus artistas por tiempo, rachas, horario y descubrimientos.',
      'Copia de seguridad en la nube: ajustes, automatizaciones y gustos, una vez al día.',
      'En un teléfono nuevo, SmartBuds te ofrece restaurar tu copia.',
    ],
  ),
  (
    version: 21,
    title: 'Automatizaciones',
    items: [
      'Crea tus propios comandos: «vamos al gimnasio» → volumen al 80 y música para entrenar.',
      'También al conectar tus audífonos o a una hora, con plantillas listas.',
      'Enlaces smartbuds:// para Atajos de iPhone, Tasker o etiquetas NFC.',
    ],
  ),
  (
    version: 20,
    title: 'Un cerebro más justo',
    items: [
      'Un solo salto ya no descarta una canción, y «Para ti ahora» mezcla más artistas.',
      'Cada sugerencia muestra el dato en que se basa, y si te conoce poco te lo dice.',
      'Las animaciones respetan «reducir movimiento» y se apagan con batería baja.',
    ],
  ),
  (
    version: 19,
    title: 'Todos tus dispositivos',
    items: [
      'Centro multidispositivo: mira qué suena en tus otros teléfonos y «Continuar aquí».',
      'Modo carro: botones grandes y voz siempre activa. Se abre solo con el Bluetooth del carro o diciendo «modo carro».',
      'La notificación de SmartBuds trae «Me gusta».',
    ],
  ),
  (
    version: 18,
    title: 'Herramientas de audio',
    items: [
      'Dispositivos → Herramientas de audio: abre el ecualizador de tu teléfono y mira la calidad de la salida.',
      'Transiciones suaves (Android): baja y sube el volumen al cambiar de canción.',
      'Límite de volumen por audífono y análisis de cada sesión en Mi música.',
    ],
  ),
  (
    version: 17,
    title: 'Escuchar juntos',
    items: [
      'Abre una sala y tus amigos escuchan la misma canción al tiempo, cada uno en su app.',
      'Vota 👍 / 👎 en las listas compartidas y pon la más votada.',
      'Insignias, desafíos semanales y tendencias de tu círculo (sin decir quién).',
    ],
  ),
  (
    version: 16,
    title: 'Experiencia inmersiva',
    items: [
      'Toca la carátula: modo inmersivo a pantalla completa (desliza hacia abajo para salir).',
      'Carátulas vivas y fondo que toma el color de la portada.',
      'En Android, el visualizador sigue el audio real si el teléfono lo permite.',
    ],
  ),
  (
    version: 15,
    title: 'Cerebro musical',
    items: [
      '«Para ti ahora»: sugerencias con su porqué que aprenden de lo que terminas o saltas.',
      'Entiende cómo te sientes: «estoy nostálgico», «me siento con energía».',
      'Radar de artistas nuevos y lo que hace buenas tus sesiones.',
    ],
  ),
  (
    version: 14,
    title: 'Privacidad y ayuda',
    items: [
      'Modo privado: escucha sin que se guarde nada («modo privado»).',
      'Mira qué datos usa SmartBuds, bórralos por periodo y descárgalos en tabla.',
      'Centro de diagnóstico, reporte de errores con tu permiso y funciones de prueba.',
    ],
  ),
  (
    version: 13,
    title: 'Contexto y personalización',
    items: [
      'Tu rutina musical, modo viaje y «sube la energía poco a poco».',
      'Inicio personalizable, modo compacto y colores de la carátula.',
      'Perfiles Diario, Estudio y Viaje; comandos rápidos editables.',
    ],
  ),
  (
    version: 12,
    title: 'Audífonos y conexión',
    items: [
      'Historial de conexiones y aviso de conexión inestable.',
      'Audífonos preferidos, tiempo de respuesta y solución de problemas.',
    ],
  ),
  (
    version: 11,
    title: 'Diseño de vidrio',
    items: ['Barra lateral de vidrio con mini reproductor y modo noche.'],
  ),
  (
    version: 10,
    title: 'Búsqueda y organización',
    items: [
      'Busca por época, versión (acústica, en vivo…) o descripción.',
      'Listas de 15 a 60 minutos, actuales vs. clásicos y limpieza de duplicados.',
    ],
  ),
  (
    version: 9,
    title: 'Inteligencia musical',
    items: ['«¿Por qué esta?», parecidas, cambios de gusto y tu evolución.'],
  ),
];

/// Qué funciona en cada versión de SmartBuds.
const compatibility = <({String feature, String web, String android, String iphone})>[
  (feature: 'Control por voz', web: 'Con la página abierta', android: 'Sí, también con pantalla apagada', iphone: 'Con la app abierta'),
  (feature: 'Ver qué suena en otras apps', web: 'No', android: 'Sí (YouTube Music, Spotify…)', iphone: 'Solo Apple Music'),
  (feature: 'Siguiente / pausa / volumen', web: 'Solo en la web', android: 'Sí', iphone: 'Apple Music; volumen no'),
  (feature: 'Toques en los audífonos', web: 'No', android: 'Sí', iphone: 'No'),
  (feature: 'Carátula y progreso', web: 'Sí (YouTube)', android: 'Sí', iphone: 'Apple Music'),
  (feature: 'Pausar en llamadas', web: 'No', android: 'Sí', iphone: 'Lo hace Apple Music'),
  (feature: 'Historial de audífonos', web: 'No', android: 'Sí', iphone: 'Parcial'),
  (feature: 'Aprender tus gustos', web: 'Sí', android: 'Sí', iphone: 'Sí'),
  (feature: 'Cuenta y sincronización', web: 'Sí', android: 'Sí', iphone: 'Sí'),
];
