# Qué funciona dónde (regla de SmartBuds)

Cada función nueva indica **en qué plataformas funciona, qué permisos necesita y de qué depende**.
No prometemos nada que Spotify, Apple Music, YouTube, Bluetooth o el sistema operativo no permitan.

| Función | Android | iPhone | Web | Permisos | Depende de |
|---|---|---|---|---|---|
| Control por voz | Sí (también con pantalla apagada) | Con la app abierta | Con la página abierta | Micrófono | Vosk (Android), Speech (iPhone), Web Speech (web) |
| Ver y controlar otras apps | Sí | Solo Apple Music | No | Acceso a notificaciones (Android), Apple Music (iPhone) | MediaSession (Android), MediaPlayer (iPhone) |
| Carátula y progreso | Sí | Apple Music | YouTube | — | Lo que comparta la app de música |
| **Cerebro musical** (recomendar, aprender, «Para ti ahora») | Sí | Sí | No (aún) | Ninguno | Tu historial en el teléfono |
| Reconocimiento de ambiente («estoy nostálgico») | Sí | Sí | Parcial | Micrófono | Reconocimiento de voz |
| Inteligencia de sesiones | Sí | Sí | No | Ninguno | Tu historial |
| Radar de descubrimiento | Sí | Sí | No | Internet | API pública de Deezer |
| Parecidas / «¿por qué esta?» | Sí | Sí | No | Internet (parecidas) | Deezer; datos propios |
| Volumen exacto | Sí | No (iOS no lo permite) | No | — | AudioManager |
| Pausar en llamadas | Sí | Lo hace Apple Music | No | — | Modo de audio de Android |
| Toques en los audífonos | Sí | No | No | — | Pausa/reanudar del reproductor |
| Clima | Sí | Sí | No | Internet (ubicación aproximada, sin GPS) | ipwho.is + Open-Meteo |
| Amigos y listas compartidas | Sí | Sí | No (aún) | Cuenta | Supabase |
| Escucha sincronizada | Sí (cualquier app) | Solo Apple Music | No | Cuenta | Supabase; saltar al segundo exacto solo si la app de música lo permite. No transmite audio: cada quien escucha en su app y cuenta |
| Votación en listas | Sí | Sí | No | Cuenta | Supabase |
| Insignias y desafíos | Sí | Sí | No | Ninguno | Tu historial (no se comparte) |
| Tendencias de tu círculo | Sí | Sí | No | Cuenta | Artistas favoritos de 2+ amigos mutuos, sin nombres |
| Datos del sonido (ritmo, energía) | **No** | **No** | **No** | — | Ninguna app de música los comparte |
| Ecualizador del sistema | Por evaluar | No (iOS no lo permite) | No | — | Depende del fabricante |
| Modo inmersivo y carátulas vivas | Sí | Sí | No | Ninguno | Carátula que comparta la app de música |
| Visualizador con el audio real | Sí (si el fabricante lo permite) | No (iOS no deja leer el audio de otras apps): animación | No | Micrófono (ya concedido) + ajustes de audio | Visualizer de Android (sesión 0) |
| Fondo con el color de la carátula | Sí | Sí | No | Ninguno | Carátula |
| Letras sincronizadas | **No por ahora** | **No por ahora** | **No por ahora** | — | Requiere un proveedor con licencia (p. ej. API comercial de Musixmatch); las fuentes gratuitas no tienen permiso de los autores |
| Escucha sincronizada | Por evaluar | Por evaluar | Por evaluar | Cuenta | Cada persona necesita poder controlar su propia app |
