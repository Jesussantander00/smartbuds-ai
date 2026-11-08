# SmartBuds en iPhone

La app de iPhone sale del **mismo código Flutter** que la de Android. Lo único
distinto es el puente nativo: en Android es Kotlin (`android/app/src/main/kotlin`),
en iPhone es Swift (`ios/Runner/AppDelegate.swift`). Los dos hablan con Dart por
los mismos canales (`smartbuds/media`, `smartbuds/voice`), así que comandos,
perfil musical, búsqueda y cuenta son iguales en las dos plataformas.

## Qué hace cada plataforma

| Función | Android | iPhone |
|---|---|---|
| Detectar el reproductor activo | Sí (cualquier app con controles en la notificación) | Solo Apple Music |
| «Cambia», «Pausa», «Continúa», «Devuelve» | Sí, en la app que suene | Sí, en Apple Music |
| «Busca …» | Sí (YouTube Music invisible, u otras apps) | Sí, en Apple Music (con suscripción) |
| YouTube Music, Spotify, Amazon… | Sí | No: iOS no deja controlar otras apps |
| Volumen por voz | Sí | No: iOS no lo permite (botones del teléfono) |
| Pantalla apagada | Sí | La música de Apple Music sigue (suena en la app Música). La escucha de voz con el iPhone bloqueado **no está garantizada**: hay que probarla en un iPhone real |
| Reconocimiento de voz | Vosk, sin internet | El de Apple; dentro del teléfono si el modelo de español está descargado |
| «Solo mi voz» | Sí | Todavía no |
| Accesos rápidos y widget | Sí | Todavía no |
| Guardar ajustes y perfil | Archivo propio de la app | Archivo propio de la app (antes se perdía al cerrar: corregido) |

## Cómo controla Apple Music

- `MPMusicPlayerController.systemMusicPlayer`: es el reproductor de la app Música.
  SmartBuds le manda reproducir, pausa, siguiente y anterior, y lee qué canción suena.
- «Busca …»: SmartBuds busca la canción en el catálogo público de Apple
  (iTunes Search, sin clave) y la pone en Música con su identificador.
- Requisitos: permiso «Apple Music» (lo pide la app) y una suscripción de
  Apple Music en la cuenta de la persona. No necesita el servicio MusicKit.

## Cómo probarla sin Mac

1. Crea una cuenta gratis en [codemagic.io](https://codemagic.io) con tu GitHub.
2. Agrega el repositorio `smartbuds-ai`. Codemagic encuentra `codemagic.yaml`.
3. Ejecuta el flujo **«iPhone · comprobar que compila»**: corre las pruebas y
   compila la app de iPhone sin firmar. Si algo del código Swift falla, ahí se ve.

## Para instalarla en un iPhone

- Hace falta la **cuenta de desarrollador de Apple (99 USD al año)** para firmar
  la app y repartirla con TestFlight. Con esa cuenta, Codemagic puede firmar y
  subir la app sin Mac.
- Alternativa sin pagar: con una Mac y Xcode se puede instalar en tu propio
  iPhone con un Apple ID gratis, pero caduca a los 7 días.

## Pendiente de probar en un iPhone real

Compilar no demuestra que funcione. Antes de darlo por bueno hay que probar:

1. **Permiso de Apple Music**: aparece en la bienvenida y queda concedido.
2. **«Busca …»**: la canción del catálogo empieza a sonar en Música. SmartBuds
   solo dice que sonó si `prepareToPlay` no dio error (sin suscripción o con la
   canción no disponible en el país, avisa que no pudo).
3. **Pantalla bloqueada**: cuánto tiempo sigue entendiendo «Cambia». Declarar
   «audio en segundo plano» no garantiza que el reconocimiento de voz siga
   indefinidamente; iOS puede detenerlo.
4. **Llamadas y Siri**: que la escucha se reanude sola al terminar.
