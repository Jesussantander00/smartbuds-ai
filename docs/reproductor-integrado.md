# Jarvis siempre disponible y reproducción integrada (PR #44)

## Cómo funcionaba antes
- **Buscar** («busca Feid»): el `CommandRouter` mandaba la búsqueda a una app externa (YouTube Music por defecto en Android, Apple Music en iPhone). SmartBuds no reproducía nada: existía un `InAppPlayer.kt` en Android sin conectar a Dart.
- **Al abrir**: Jarvis arrancaba solo (PR #34) si había permiso, pero **no recordaba** si lo habías apagado a propósito, y sin permiso no lo decía en pantalla.
- **Después de cada orden**: el ciclo continuo ya se reparó en #34 (causas: tareas viejas de iPhone que mataban la nueva, `onTimeout` de Android sin reabrir, web con escucha continua apagada) y #38 (bucle de sesión de audio en iPhone). Este PR lo conserva y lo prueba con el reproductor nuevo.

## Fuentes y qué permiten (revisado)

| Fuente | ¿Suena dentro de SmartBuds? | Cómo | Límite real |
|---|---|---|---|
| **YouTube** | Sí, completa | Reproductor **oficial** incrustado (IFrame API) en un WebView | Necesita tu clave de YouTube Data API para buscar (`secrets.json`). El video **se ve** (mín. 200×200) y **se pausa al salir** de la app: YouTube no permite audio oculto ni en segundo plano. Algunos videos no se dejan incrustar (se pasa al siguiente). |
| **Audius** | Sí, completa | API pública con `app_name`; reproductor nativo (Android MediaPlayer / iPhone AVPlayer) | Catálogo de artistas independientes: casi nunca tiene éxitos comerciales. Solo se usa si coincide con lo pedido. Sigue con la pantalla apagada. |
| **Deezer** | Solo 30 s | Vista previa oficial de su API | La canción completa solo en la app de Deezer. Se dice claramente («solo tengo la vista previa»). |
| **Spotify** | No | — | Su SDK controla la app de Spotify; la Web Playback SDK es solo web y Premium. No se finge. |
| **Apple Music** | Hoy no | — | MusicKit permitiría reproducir dentro con suscripción, pero exige cuenta de desarrollador de pago y permiso de MusicKit. |

Nada de extracción de audio ni reproductores simulados. Si ninguna fuente integrada la tiene, Jarvis lo dice y la busca en tu app de música.

## Qué cambió
- **Reproductor integrado** (`lib/features/player/`): búsqueda separada de la reproducción (`MusicCatalog`), motores (`YouTubeEngine`, `NativeAudioEngine`) y `SmartBudsPlayer` (cola de resultados, estado, posición, volumen propio).
- **Barra del reproductor** visible en todas las secciones: portada (o el video), título, artista, fuente honesta («Completa · YouTube», «Vista previa 30 s · Deezer»), progreso, anterior / pausa / siguiente y resultados.
- **Jarvis lo controla**: «busca…», «cambia», «pausa», «sube» (volumen **del reproductor**, no el del teléfono), «anterior», «adelanta», «deshacer». La cola de SmartBuds, los viajes, las actividades, la radio y el perfil funcionan igual (el reproductor se presenta como «SmartBuds»).
- **Buscar en Inicio** muestra los resultados dentro de SmartBuds.
- **Ajuste** «Reproducir dentro de SmartBuds» (activado). «… en Spotify» sigue abriendo esa app.
- **Jarvis al abrir**: arranca solo si diste permiso y «Escuchar al abrir SmartBuds» está activado; si apagas el micrófono, lo recuerda. Estado nuevo **«Micrófono sin permiso»** con botón que pide el permiso oficial. La pastilla dice «Escucha desactivada» cuando está apagado.
- **Web**: ya reproducía dentro de la página con el reproductor oficial de YouTube («Aquí mismo», por defecto) y arranca la escucha si el navegador ya dio permiso (#34).

## Cuidados con #34, #35, #36 y #38
- La escucha y la memoria de conversación no cambian; «pon una de él» usa el artista que suena en SmartBuds.
- El reproductor de iPhone usa la misma sesión de audio de Jarvis (no la reconfigura: el arreglo de #38 sigue). En Android pide foco de audio solo para **reproducir**, nunca para escuchar.
- El volumen de la música de SmartBuds lo cambia el reproductor, no el volumen del sistema.

## Pruebas en el teléfono
1. Abre la app: Jarvis empieza a escuchar sin tocar nada (con permiso).
2. Di cinco órdenes seguidas sin tocar el micrófono.
3. «Busca Feid Normal»: suena en la barra de SmartBuds (con clave de YouTube: el video se ve).
4. «Cambia»: siguiente resultado (o lo de la cola).
5. Da una orden con música sonando; tras la respuesta, Jarvis vuelve a escuchar.
6. Cambia de sección: la barra sigue y la música también.
7. Bloquea y desbloquea: YouTube se pausa al salir (regla de YouTube); Audius sigue.
8. Conecta y desconecta audífonos.
9. Apaga el micrófono, cierra y abre la app: sigue apagado. Enciéndelo: al volver a abrir, escucha solo.
10. Sin permiso de micrófono: aparece «Micrófono sin permiso» y «Dar permiso».
11. Habla o canta encima: el volumen no cambia.
