# SmartBuds AI — Módulo 1: Active Player Detector + Connector Manager

Primer entregable de la arquitectura **SmartBuds AutoConnect**: detectar el
reproductor activo en Android, saber qué permite hacer y enviarle «Cambia» y
«Pausa» con verificación. La voz llega en el módulo 3; aquí los comandos se
lanzan con botones, que pueden simular que vienen de la voz para probar las políticas.

## Documentación

- [Arquitectura técnica y plan de desarrollo](docs/01-arquitectura-tecnica-y-plan.md)
- [Arquitectura AutoConnect](docs/02-arquitectura-autoconnect.md)

## Puesta en marcha

Requisitos: Flutter 3.22 o superior (Dart 3.3+), Android Studio y un teléfono
Android físico (en el emulador casi no hay reproductores con sesión multimedia).

```bash
cd smartbuds-ai
# Genera lo que falta de la plataforma (Gradle, recursos, ios/…).
# No sobrescribe los archivos que ya existen.
flutter create --org com.smartbuds --project-name smartbuds_ai --platforms android,ios .
flutter pub get
flutter test          # pruebas del núcleo, sin teléfono
flutter run           # con el teléfono conectado
```

Al abrir la app: **Conceder acceso** → activar *SmartBuds AI* en *Acceso a
notificaciones* → volver. Hay que hacerlo una sola vez.

## Qué incluye

| Pieza | Archivo |
|---|---|
| Interfaz común `MusicConnector` + `PlayerSource` | `lib/connectors/connector_interface.dart` |
| Active Player Detector (prioridades 1–4) | `lib/core/player_detector/active_player_detector.dart` |
| Capability Manager + políticas + registro | `lib/core/capability_manager/capability_manager.dart` |
| Command Router | `lib/core/command_router/command_router.dart` |
| Playback Verifier | `lib/core/command_router/playback_verifier.dart` |
| Connector Manager | `lib/core/connector_manager.dart` |
| Conector Android (Dart) | `lib/connectors/android_media/android_media_connector.dart` |
| Módulo nativo Kotlin | `android/app/src/main/kotlin/.../MediaSessionConnector.kt` |
| Servicio de notificaciones | `.../SmartBudsNotificationListener.kt` + `AndroidManifest.xml` |
| Pantalla «Reproductor detectado» | `lib/features/devices/` |
| Pruebas | `test/` |

El núcleo no tiene dependencias externas: solo Flutter.

### Flujo de un comando

`route(next)` → `ConnectorManager.candidates()` → `ActivePlayerDetector.detect()`
→ `CapabilityManager.evaluate()` → `connector.execute()` → `PlaybackVerifier.verify()`.

Resultados posibles: `verified`, `sentUnverified` (se envió pero el reproductor
no lo confirmó; nunca se presenta como éxito), `notAllowed`, `needsChoice`,
`noPlayer`, `permissionMissing` y `failed`.

### Decisiones que conviene revisar

- **Spotify**: la política por defecto bloquea los comandos que vienen de la
  **voz** hacia `com.spotify.music` (nivel *Control limitado*). Los comandos
  **manuales** pasan por los controles multimedia estándar de Android, igual que
  los botones de unos audífonos Bluetooth. Si prefieres bloquearlo todo, añade
  `CommandSource.manual` a `blockedSources` en `defaultPolicies`. Conviene
  confirmar la decisión con los términos vigentes de Spotify antes de publicar.
- **Ruta del módulo nativo**: el documento lo ubicaba en `android/native_media/`,
  pero Gradle solo compila el código Kotlin que está en
  `android/app/src/main/kotlin/`, así que está ahí.
- **Volumen**: es del sistema (`AudioManager`), no de un reproductor, así que no
  pasa por el detector ni por las políticas.
- **Último reproductor utilizado**: por ahora solo se guarda en memoria
  (`InMemoryLastUsedStore`). Se pasará a SQLite junto con el Smart Profile.
- **iOS**: la app compila y muestra el aviso de limitaciones; la fuente de
  Apple Music (MusicKit) se añade en la Fase 4 como otro `PlayerSource`.

## Pruebas en teléfono (criterios de aceptación)

| Prueba | Resultado esperado |
|---|---|
| Sin permiso | Aparece el aviso y el botón *Conceder acceso* |
| Reproductor local sonando → «Cambia» | Avanza una pista; resultado `verified` |
| «Pausa» | Se detiene; resultado `verified` |
| Spotify pausado + YouTube Music sonando → «Pausa» | Solo se pausa YouTube Music |
| Spotify sonando, modo «Como voz» → «Cambia» | `notAllowed` con el motivo; Spotify no cambia |
| Dos reproductores pausados, ninguno usado | `needsChoice` con los nombres |
| Cambiar de audífonos Bluetooth | La detección sigue funcionando |
| Registro de capacidades | Muestra lo declarado frente a lo efectivo por cada evaluación |

Apps para probar: el reproductor de música del fabricante, YouTube Music,
Apple Music para Android, VLC, Spotify y algún podcast.
