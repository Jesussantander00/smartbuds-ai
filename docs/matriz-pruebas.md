# Matriz de pruebas de SmartBuds AI

**Regla:** una función solo es «Funciona» si alguien la probó de verdad en ese equipo. Que compile o que pasen las pruebas automáticas es «Implementado», no «Funciona».

Estados: ✅ probado y funciona · ❌ probado y falla · ⏳ implementado, sin prueba real · — no aplica

Última actualización: 15 nov 2026.

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
