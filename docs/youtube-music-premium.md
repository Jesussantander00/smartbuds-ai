# «Usar mi YouTube Music Premium» (Android)

## Auditoría: cómo se mandaban las órdenes antes
`lib/core/command_router/command_router.dart` (`routeSearch`), en este orden:
1. **0a, invisible:** si YouTube Music tiene una sesión multimedia activa, `playFromUri` con el enlace de la canción (requiere clave de YouTube para encontrarla).
2. **0b, visible:** si no funcionó, abría el enlace en YouTube Music (`openUri`) y volvía a SmartBuds. **Esta era la redirección inesperada.**
3. **1, invisible:** `playFromSearch` a la sesión activa.
4. **2, visible:** intención `MEDIA_PLAY_FROM_SEARCH`, que **abre** YouTube Music.

Pausa, sigue, siguiente, anterior y volumen ya iban por `MediaController.TransportControls` a la sesión activa, sin abrir nada.

## Qué permite de verdad
- **Android (oficial):** con acceso a notificaciones, una app puede obtener los `MediaController` de las sesiones activas y usar sus controles de transporte (`play`, `pause`, `skipToNext`, `skipToPrevious`, `playFromSearch`, `playFromUri`). Que la app de música **obedezca** `playFromSearch`/`playFromUri` depende de ella.
- **YouTube Music:** no tiene una API pública para que otra app busque y reproduzca. Lo que acepte por su sesión multimedia no está documentado y puede cambiar. Si YouTube Music está **cerrado**, no hay sesión: Android no deja encenderlo sin abrir su pantalla.
- **Premium:** permite que YouTube Music siga con la pantalla apagada. No da a SmartBuds acceso a su buscador.

## Qué cambia en este PR
- **Nunca se abre una app por voz sin permiso** (con o sin el ajuste): la búsqueda por voz solo usa los caminos invisibles (0a y 1). Si haría falta abrir la app, el resultado es `needsConsent`: Jarvis pregunta «¿Lo abro?» y aparece una tarjeta en Inicio con **Abrir / Cancelar**. «Ábrelo» por voz también autoriza. El permiso vale 2 minutos y para esa canción.
- **Ajuste «Usar mi YouTube Music Premium»** (Asistente → Música): las búsquedas (voz y escritas) van a YouTube Music en lugar del reproductor de SmartBuds; si SmartBuds estaba sonando, se pausa; «sigue» reanuda YouTube Music.
- El botón «Buscarla en mi app de música» sigue abriendo la app (es un permiso explícito).
- El reproductor integrado de SmartBuds queda igual para quien no active el ajuste.

## Límites
- Con YouTube Music **cerrado del todo**, la primera canción siempre necesita abrirlo una vez (con tu permiso). Después, mientras siga en segundo plano, las demás deberían ir sin salir.
- Si YouTube Music ignora `playFromUri`/`playFromSearch` aun estando abierto, también pedirá permiso para abrirlo. Solo se sabe probándolo en el teléfono.
- Pantalla apagada: lo hace YouTube Music con Premium; SmartBuds no interviene.
- Solo Android. En iPhone ninguna app puede controlar la reproducción de otra (salvo Apple Music).

## Prueba en el teléfono (Android)
1. Activa el ajuste. Abre YouTube Music, pon cualquier canción y vuelve a SmartBuds.
2. Di «busca Feid Normal»: ¿cambió sin salir de SmartBuds? (✅/❌)
3. «Pausa», «sigue», «cambia», «anterior», «sube»: ¿obedece sin salir?
4. Apaga la pantalla: ¿sigue sonando?
5. Cierra YouTube Music por completo y di «busca Karol G Provenza»: debe **preguntar** antes de abrir. Di «ábrelo».
