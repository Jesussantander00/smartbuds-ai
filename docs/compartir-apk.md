# Compartir SmartBuds con amigos (gratis, sin Play Store)

Cada vez que se sube un cambio a `main`, Codemagic compila un **APK** de Android
(flujo «Android · APK para compartir» en `codemagic.yaml`), con los modelos de
voz incluidos.

1. Entra a [codemagic.io](https://codemagic.io) → app **smartbuds-ai** → último
   build de «Android · APK para compartir».
2. En **Artifacts** descarga `app-release.apk`.
3. Mándalo por WhatsApp o Drive. En el teléfono de tu amigo: abrir el archivo →
   permitir «Instalar apps desconocidas» → Instalar.

Para que la búsqueda de canciones y la cuenta funcionen en ese APK, en Codemagic →
Environment variables crea el grupo `smartbuds` con `YOUTUBE_API_KEY`,
`SUPABASE_URL` y `SUPABASE_ANON_KEY` (marcadas como secretas) y descomenta
`groups` en `codemagic.yaml`.

Para Play Store (pago único de 25 USD) sigue `docs/publicacion-play-store.md`.
