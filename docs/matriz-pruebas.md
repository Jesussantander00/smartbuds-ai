# Matriz de pruebas de SmartBuds AI

**Regla:** una función solo es «Funciona» si alguien la probó de verdad en ese equipo. Que compile o que pasen las pruebas automáticas es «Implementado», no «Funciona».

Estados: ✅ probado y funciona · ❌ probado y falla · ⏳ implementado, sin prueba real · — no aplica

Última actualización: 19 nov 2026 (se agrega la etapa 0 en emulador; las tablas anteriores no cambian).

## Web (https://smartbuds-ai-web.vercel.app)

| # | Prueba | PC (Chrome) | Android (Chrome) | iPhone (Safari) |
|---|---|---|---|---|
| W1 | Abre y muestra «Toca para entrar» | ✅ (navegador de Claude, 15 nov) | ⏳ | ⏳ |
| W2 | Búsqueda escrita reproduce la primera | ✅ (ídem) | ⏳ | ⏳ |
| W3 | La dirección no cambia ni abre otra app | ✅ (ídem) | ⏳ | ⏳ |
| W4 | Siguiente / anterior / pausa con botones | ✅ (ídem) | ⏳ | ⏳ |
| W5 | Se oye el audio (oído humano) | ⏳ | ⏳ | ⏳ |
| W6 | Controles propios de YouTube visibles y sin nada encima (tras este PR) | ⏳ | ⏳ | ⏳ |
| W7 | Micrófono: Jarvis pasa a «Escuchando» | ⏳ | ⏳ | ⏳ |
| W8 | Voz: «busca Feid Normal» suena | ⏳ | ⏳ | ⏳ |
| W9 | Voz: «busca una canción» → «Provenza de Karol G» suena | ⏳ | ⏳ | ⏳ |
| W10 | Voz: «cambia», «pausa», «sube» | ⏳ | ⏳ | ⏳ |
| W11 | Cinco órdenes seguidas sin tocar | ⏳ | ⏳ | ⏳ |
| W12 | Hablar o cantar no cambia el volumen | ⏳ | ⏳ | ⏳ |

Nota W1–W4: se probaron en el navegador integrado de la app de Claude, que no aplica el bloqueo de sonido de los celulares ni permite micrófono. No sustituyen la prueba en Chrome real.

## App Android (instalada desde `main` con `secrets.json` y modelo de voz)

| # | Prueba | Estado |
|---|---|---|
| A1 | Instala y abre | ⏳ |
| A2 | Jarvis escucha al abrir, sin tocar | ⏳ |
| A3 | «Busca Feid Normal» suena en la barra de SmartBuds (video visible) | ⏳ |
| A4 | No abre YouTube Music ni otra app | ⏳ |
| A5 | «Cambia», «pausa», «sube» controlan el reproductor de SmartBuds | ⏳ |
| A6 | Cinco órdenes seguidas | ⏳ |
| A7 | Buscar escrito muestra resultados unificados con su fuente | ⏳ |
| A8 | Audius: canción completa, sigue con pantalla apagada | ⏳ |
| A9 | Vista previa de 30 s marcada como tal | ⏳ |
| A10 | Hablar o cantar no cambia el volumen | ⏳ |
| A11 | Bloquear / desbloquear, conectar / quitar audífonos | ⏳ |
| A12 | Apagar micrófono, cerrar y abrir: sigue apagado | ⏳ |

## Etapa 0 — línea base en emulador Android (19 nov 2026)

> **Resultados de la etapa 0 en emulador Android; las pruebas en un dispositivo real siguen pendientes.**
> Esta tabla es una validación parcial y no reemplaza la prueba en un teléfono. Por eso las filas A1–A12 de arriba siguen en ⏳.

**Entorno**
- Emulador: Medium Phone, Android 17 (API 37), con Google Play, x86_64, en un PC con Windows.
- Versión: debug, generada con `flutter run --dart-define-from-file=secrets.json`.
- Rama `main`, commit `125a5f3`.
- Audio: audífonos y micrófono del PC, a través del micrófono virtual del emulador.
- Quién probó: el usuario habló y cantó; Claude observó y tocó la pantalla en el panel Running Devices de Android Studio.
- No se modificó código, `Assistant`, dependencias ni configuración nativa.

Estados de esta tabla: ✅ funciona en el emulador · ⚠️ parcial · ❌ falla o no se probó (se indica cuál).

| # | Prueba | Resultado | Observación |
|---|---|---|---|
| E1 | «Reproduce [canción]» muestra resultados con fuente y disponibilidad | ✅ | La lista «Resultados para…» marca cada resultado como «Completa · YouTube», «Completa · Audius» o «Vista previa 30 s · Deezer / Apple». Se dijo «Reproduce Feid Normal», se entendió «busca normal» y aun así sonó «Normal» de Feid. |
| E2 | Elegir una pista por voz y por toque | ✅ | Por toque, el resultado 2 (Audius) sonó. Por voz, «la segunda» funcionó, con unos 10 s de demora. |
| E3 | Audius suena dentro de SmartBuds | ✅ | deadmau5 sonó completa (3:30) dentro de la app. |
| E4 | Audius sigue con la pantalla bloqueada | ⚠️ parcial | Con la pantalla apagada 15–19 s siguió sonando (de 0:16 a 0:35). No se probó un bloqueo real con PIN, más tiempo ni audífonos. No hay controles en la pantalla de bloqueo ni en la notificación (etapa 3). |
| E5 | YouTube suena en el reproductor oficial (WebView) con la app abierta | ✅ | «Normal» y «Sígueme (Remix)» sonaron dentro de la app, con los controles oficiales de YouTube y sin capas encima. No salió de la app. |
| E6 | YouTube se pausa al salir o al bloquear la pantalla | ✅ | Se pausó al ir a Inicio y al apagar la pantalla. Al volver queda en pausa y hay que tocar ▶. |
| E7 | YouTube Music se abre solo con permiso explícito | ❌ no probado | El emulador no tiene YouTube Music, que pide iniciar sesión con una cuenta de Google. |
| E8 | Jarvis escucha al abrir la app y después de cada orden | ⚠️ parcial | La primera apertura, tras la configuración inicial, mostró «Jarvis está desactivado». Al reabrir desde recientes sí escuchaba, pero el proceso no se había cerrado: el servicio de escucha lo mantiene vivo y el punto verde del micrófono seguía encendido. El arranque con el proceso completamente cerrado no está probado. Después de cada orden sí siguió escuchando, salvo la incidencia I3. |
| E9 | Hablar o cantar no cambia el volumen | ✅ | El usuario habló y cantó unos 15 s con música y el volumen no se movió. |
| E10 | Órdenes actuales: pausa, siguiente, anterior, volumen, «la primera», «agrega a la cola» | ⚠️ parcial | Pausa, sigue, siguiente, anterior, sube y baja funcionan, con unos 10 s de demora cada una. «Agrega a la cola…» falló: se entendió «hola». |
| E11 | Avance automático al terminar una canción | ❌ falla | No pasa a la siguiente pista ni con Audius ni con YouTube. En YouTube queda la pantalla final con videos sugeridos. «Radio SmartBuds» estaba apagado, pero la lista de resultados tampoco avanza: no hay una cola que avance sola (etapa 2). |

### Incidencias (no son funciones terminadas)

| # | Incidencia | Dónde se vio | Siguiente paso |
|---|---|---|---|
| I1 | No hay avance automático de la cola al terminar una pista | E11 | Etapa 2: una sola cola de `Track` en `SmartBudsPlayer`, con el evento de fin de reproducción. |
| I2 | Unos 10 s de demora en cada orden de voz | E2, E10 | Medir dónde se va el tiempo: reconocimiento, interpretación de la orden, canal nativo o reproductor. Repetir en un teléfono real, porque el emulador simula el procesador. |
| I3 | La voz se trabó unos 9 minutos (8:38–8:47): solo llegaba «busca», aun reiniciando a Jarvis | Sesión de voz | Volvió después de apagar y prender el micrófono virtual del emulador y de poner una canción. Causa sin confirmar (emulador, servicio de escucha o app). Queda como incidente no reproducido; probar en Android físico. |
| I4 | «Agrega a la cola…» se entiende como «hola» | E10 | Revisar el reconocimiento y la interpretación. No es necesariamente un problema del reproductor. |
| I5 | Desbordes en pantallas angostas: «RIGHT OVERFLOWED BY 0.400 PIXELS» en el menú lateral, y «Jarvis / Escuchando» en columna, una letra debajo de otra, en Inicio | Inicio | Corregir antes de una demo pública. |
| I6 | Arranque inicial de Jarvis inconsistente | E8 | Probar un arranque real desde cero, sin proceso previo. |

### Pendiente en un Android físico (para cerrar la etapa 0)
- YouTube Music se abre solo con permiso explícito (E7).
- Audius sigue varios minutos con la pantalla bloqueada con PIN (E4).
- Los audífonos Bluetooth controlan play, pausa, siguiente y anterior.
- La notificación multimedia aparece y funciona.
- Jarvis arranca con el proceso totalmente cerrado (E8, I6).
- La voz funciona estable durante más de 10 minutos (I3).
- Se confirma si el bloqueo de voz fue del emulador o de la app (I3).
- La demora de las órdenes en hardware real (I2).

## App iPhone

Mismas pruebas A1–A12. Estado: ⏳ todas. Además no hay forma de instalarla hoy sin Mac o cuenta de desarrollador de Apple: solo se comprueba que compila.

## Pruebas automáticas (no cuentan como «Funciona»)
- `flutter test`: lógica (parser, cola, buscador, reproductor simulado). Pasa en `main`.
- `en-vivo`: Deezer, Apple (iTunes) y Audius responden y su audio se descarga. Pasa.
- Compilación de Android (APK) e iPhone (sin firmar). Pasa.

## Auditoría de proveedores (15 nov 2026)

| Proveedor | Reproducción integrada | Condiciones verificadas | Decisión |
|---|---|---|---|
| YouTube | Sí, reproductor oficial incrustado | Mínimo 200×200; sin capas encima; reproducción automática solo con el reproductor a la vista; identificarse con el origen | En uso. Este PR quita la capa y devuelve los controles oficiales |
| Audius | Sí, canción completa por su API | API gratuita; pide `app_name` y dar crédito al artista; hay Términos de API y licencia abierta (OML) desde jul 2025 que conviene leer antes de publicar | En uso en la app; pendiente en la web |
| Apple Music (MusicKit) | Sí, con suscripción del usuario; web, iOS y Android | Exige membresía de pago del Apple Developer Program para el token de desarrollador | No iniciar: genera gasto |
| Deezer / Apple iTunes | Solo 30 s | Vista previa oficial | En uso como muestra, marcada |
| Spotify | No viable | Prohíbe control por voz; modo desarrollo exige Premium y máx. 5 usuarios | Desactivado; Jarvis no lo maneja |
