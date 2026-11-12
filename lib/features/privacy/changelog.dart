/// Novedades de SmartBuds, de la más reciente a la más antigua.
/// Subir [latestChangelog] cuando se agrega una entrada.
const latestChangelog = 17;

const changelog = <({int version, String title, List<String> items})>[
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
