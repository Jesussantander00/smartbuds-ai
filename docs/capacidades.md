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
| Datos del sonido (ritmo, energía) | **No** | **No** | **No** | — | Ninguna app de música los comparte |
| Ecualizador del sistema | Por evaluar | No (iOS no lo permite) | No | — | Depende del fabricante |
| Letras sincronizadas | Por evaluar | Por evaluar | Por evaluar | — | Requiere licencia de un proveedor de letras |
| Escucha sincronizada | Por evaluar | Por evaluar | Por evaluar | Cuenta | Cada persona necesita poder controlar su propia app |
