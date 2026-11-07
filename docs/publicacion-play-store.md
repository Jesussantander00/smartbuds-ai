# Publicar SmartBuds AI en Google Play — lista de pasos

## Lo que necesitas tú

1. **Cuenta de desarrollador de Google Play** (pago único de 25 USD).
2. **Probar en un teléfono Android real** con Android 11 o superior: pantalla apagada, audífonos Bluetooth y «Solo mi voz».
3. **Ícono y nombre definitivos.** Ícono de 512×512 px y una imagen destacada de 1024×500 px.

## Firma de la app

1. Crear la llave de firma (una sola vez; guárdala y no la pierdas nunca):
   ```
   keytool -genkey -v -keystore smartbuds-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias smartbuds
   ```
2. Crear `android/key.properties` (excluido de GitHub) con la ruta y las contraseñas.
3. Configurar `signingConfigs.release` en `android/app/build.gradle.kts`.
4. Generar el paquete: `flutter build appbundle --dart-define-from-file=secrets.json`

## Seguridad

- Clave de YouTube nueva, restringida a la app Android (paquete + SHA-1) y solo a YouTube Data API v3. Borrar la clave usada en pruebas.
- Supabase: pasar de `device_id` a inicio de sesión (Supabase Auth) y limitar las políticas a `auth.uid()`.

## Ficha de la tienda

- **Política de privacidad** publicada en una URL (texto en `docs/politica-de-privacidad.md`).
- **Declaración de permisos sensibles**: micrófono en segundo plano (servicio de primer plano de tipo micrófono) y acceso a notificaciones. Google pide un video corto mostrando por qué la app los necesita.
- **Seguridad de los datos**: declarar título/artista de canciones y huella de voz (guardados en el dispositivo).
- Capturas de pantalla: Inicio, Asistente, Mi música.

## Texto sugerido

**Nombre:** SmartBuds AI — Música por voz

**Descripción corta:** Controla tu música con la voz, sin tocar el teléfono.

**Descripción:** Di «Cambia» y pasa la canción. Di «Busca» y el nombre, y suena al instante. SmartBuds funciona con YouTube Music, Apple Music y otras apps, también con la pantalla apagada, y aprende lo que te gusta para ponerte la música correcta en cada momento del día.
