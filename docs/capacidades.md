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
| Ecualizador | Abre el del teléfono (si el fabricante lo trae) | No (se usa Ajustes → Música → Ecualizador) | No | — | Panel de efectos del sistema; SmartBuds no ecualiza otras apps |
| Analizador de calidad de salida | Sí: tipo, nombre, frecuencias, canales, búfer | Parcial: salida, frecuencia, latencia | No | — | AudioManager (Android), AVAudioSession (iPhone). El códec Bluetooth no se expone |
| Transiciones suaves | Sí (baja y sube el volumen) | No (iOS no deja cambiar el volumen) | No | — | AudioManager. No es crossfade real: no se mezclan dos canciones |
| Perfil de sonido por audífono | Sí: volumen guardado y límite | Solo se muestra; sin control de volumen | No | Bluetooth | AudioManager |
| Análisis de reproducción | Sí | Sí | No | Ninguno | Tu historial en el teléfono (tiempo escuchado estimado) |
| Modo inmersivo y carátulas vivas | Sí | Sí | No | Ninguno | Carátula que comparta la app de música |
| Visualizador con el audio real | Sí (si el fabricante lo permite) | No (iOS no deja leer el audio de otras apps): animación | No | Micrófono (ya concedido) + ajustes de audio | API `Visualizer` de Android sobre la salida general (sesión 0). No es captura de audio (`AudioPlaybackCapture`, que exige proyección de pantalla y que la app de origen lo permita). Varios fabricantes la bloquean o entregan silencio: tras 3 s de silencio vuelve a la animación, y si en 10 s nunca llegó sonido apaga la captura. Sin animación con «reducir movimiento» o batería baja |
| Fondo con el color de la carátula | Sí | Sí | No | Ninguno | Carátula |
| Letras sincronizadas | **No por ahora** | **No por ahora** | **No por ahora** | — | Requiere un proveedor con licencia (p. ej. API comercial de Musixmatch); las fuentes gratuitas no tienen permiso de los autores |
| Centro multidispositivo (ver qué suena en tus otros dispositivos) | Sí | Sí | No (aún) | Cuenta | Supabase (`supabase/dispositivos.sql`); una fila por dispositivo, sin historial, solo tu cuenta la ve; nada en modo privado |
| «Continuar aquí» | Sí | Solo Apple Music | No | Cuenta | Busca la misma canción en este teléfono; no sigue en el segundo exacto |
| Controlar la música de otro teléfono a distancia | **No** | **No** | **No** | — | El sistema solo deja controlar la música del propio teléfono |
| Modo carro (pantalla simple + voz) | Sí; se abre solo con el Bluetooth del carro | Sí (abrir con voz o botón) | No | Micrófono | Pantalla propia de SmartBuds. Usar con el carro detenido |
| Android Auto / CarPlay | **No** | **No** | — | — | Solo aceptan apps que reproducen su propia música (CarPlay además exige permiso especial de Apple) |
| Reloj | Controles de música del reloj (Wear OS) + «Me gusta» en la notificación | «Ahora suena» del Apple Watch | No | — | Controles del sistema. App propia para el reloj: no por ahora (Wear OS y watchOS exigen una app aparte) |
| Comandos personalizados («vamos al gimnasio» → varios pasos) | Sí | Sí | No | Micrófono | Reconocimiento de voz del teléfono; cada paso es una orden que SmartBuds ya entiende |
| Automatización al conectar audífonos | Sí | Solo si la app está abierta | No | Bluetooth | Aviso de audífonos del sistema |
| Automatización a una hora | Sí, con SmartBuds abierto o escuchando en segundo plano | Solo con la app abierta | No | — | Temporizador de la app. Con la app cerrada del todo no se despierta sola |
| Enlaces smartbuds:// (Atajos, Tasker, MacroDroid, NFC) | Sí | Sí (app Atajos) | No | — | Esquema de URL propio; solo acciones que ya existen en la app |
| Hogar inteligente (Google Home, Alexa) | **No por ahora** | **No por ahora** | — | — | Exigen registrar la app como dispositivo o «skill» en sus servicios en la nube. Los Atajos y Tasker sí pueden disparar SmartBuds |
| Estadísticas avanzadas (artistas por tiempo, rachas, horario, descubrimientos) | Sí | Sí | No | Ninguno | Tu historial en el teléfono. Sin género ni álbum: las apps de música no los comparten |
| Copia de seguridad en la nube | Sí | Sí | No | Cuenta | Supabase (`supabase/respaldo.sql`): una copia por cuenta, solo tú la ves, máx. ~2 MB. Sin sesión ni huella de voz |
| Copia como texto (exportar / importar) | Sí | Sí | — | — | Compartir o portapapeles |
