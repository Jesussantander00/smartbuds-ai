# Escucha continua de Jarvis (PR #34)

## Qué fallaba (causa raíz)

| Plataforma | Problema | Efecto |
|---|---|---|
| iPhone | Al reiniciar la escucha se cancelaba la tarea de reconocimiento; su aviso de «cancelada» llegaba **después** y reiniciaba —matando— la tarea nueva, en bucle. | Jarvis funcionaba una vez y luego quedaba sordo hasta tocar el micrófono. |
| iPhone | Al conectar/quitar audífonos (cambio de ruta) el motor de audio se detiene solo y nadie lo reabría; tampoco al volver a la app. | Dejaba de escuchar sin avisar. |
| iPhone | Tras un error no se avisaba a Dart que el micrófono estaba cerrado. | La pantalla decía «Escuchando» sin escuchar. |
| Android | `onTimeout` cerraba el micrófono y no volvía a abrirlo; los errores se reintentaban cada 1,5 s para siempre. | Sordo en silencio / gasto de batería. |
| Android | Un cambio de modo (música sonando ↔ no) podía abrir el reconocedor mientras «¿Qué canción?» usaba el micrófono. | Dos reconocedores a la vez. |
| Web | La escucha continua venía **apagada**; el micrófono escuchaba una sola frase; tocarlo no la detenía; la voz de respuesta se escuchaba a sí misma; errores en bucle cada 0,4 s. | Exactamente: «toco, funciona una vez, deja de responder». |
| Dart | Ningún vigilante: si el lado nativo se caía en silencio, nadie lo notaba. | Sin recuperación ni mensaje. |

## Qué cambió

- **Máquina de estados** (`JarvisState`): Desactivado, Preparado, Escuchando, Procesando, Ejecutando, Respondiendo, Recuperando y Error. Se ve en el núcleo de Jarvis, el panel de Inicio y la pastilla de las demás secciones.
- **Vigilante en Dart** (cada 4 s): si debería escuchar y no escucha por 8 s, pide al teléfono reabrir el micrófono (`ensure`). Máximo 3 intentos con pausas crecientes (8, 16, 32 s); después pasa a **Error** con botón **Reintentar**. Nunca reintenta sin fin.
- **Al volver a la app** (desbloquear, regresar de otra app): se comprueba y reabre la escucha.
- **iPhone**: número de tarea para ignorar respuestas viejas, un solo reinicio pendiente, reapertura al cambiar audífonos, al reactivarse la app y tras cambios del motor de audio, y pausas crecientes ante errores (máx. 5, luego error claro).
- **Android**: nunca dos reconocedores (bloqueo durante «¿Qué canción?»), reapertura tras `onTimeout`, pausas crecientes (1,5 s → 15 s, máx. 5) y luego error claro; nuevo método `ensure`.
- **Web**: escucha continua activada por defecto; arranca sola si ya diste permiso de micrófono; el micrófono enciende/apaga a Jarvis; no se escucha mientras habla; pausas crecientes ante errores; se detiene en otra pestaña y se reabre al volver.
- Registro de diagnóstico de la escucha (`diagnostics`) para el autodiagnóstico.

## Límites reales de cada sistema

- **Android**: escucha también con la pantalla apagada (servicio en primer plano con aviso, permitido). En el **emulador** hay que activar el micrófono del PC: *Extended controls → Microphone → «Virtual microphone uses host audio input»*.
- **iPhone**: escucha mientras SmartBuds está abierto, y en segundo plano solo mientras la sesión de audio siga activa (el sistema puede cortarla: llamadas, Siri, otra app que usa el micrófono). Al volver se reabre sola. No se promete escucha permanente con la app cerrada.
- **Web**: el navegador exige un toque la primera vez (permiso). En otra pestaña no escucha. En iPhone, desde el ícono de inicio Safari no permite la voz.
- No se graba ni guarda audio; en modo privado no se guarda lo escuchado.

## Cómo probarlo en un teléfono real

Marca ✅/❌ y anota qué pasó.

**Android (y emulador con micrófono del PC activado)**
1. Abre SmartBuds (bienvenida ya hecha y permiso de micrófono dado). Sin tocar nada di «cambia». → Debe cambiar.
2. Di cinco órdenes seguidas: «pausa», «sigue», «sube», «baja», «cambia».
3. Di «busca una canción» → responde «¿Qué canción?» → di el nombre → la pone → di «cambia» (sin tocar).
4. Ve a Mi música y Amigos y vuelve a Inicio; da una orden.
5. Bloquea el teléfono 1 minuto, desbloquéalo y da una orden.
6. Conecta y desconecta los audífonos Bluetooth; da una orden.
7. Toca el micrófono para apagar: la notificación desaparece y no responde. Tócalo otra vez: vuelve.
8. Di «deja de escuchar»: se apaga.
9. Quita el permiso de micrófono en Ajustes, vuelve: debe decir claramente que falta el permiso.

**iPhone**: los mismos pasos 1–8 (paso 5 con la app abierta antes de bloquear) y además: recibe una llamada y cuelga → debe volver a escuchar.

**Web** (Chrome en PC o Android): abre la página, toca el micrófono una vez, di tres órdenes seguidas; recarga la página: debe escuchar sola; cambia de pestaña y vuelve.
