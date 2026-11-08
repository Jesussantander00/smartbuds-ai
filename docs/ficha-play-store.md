# Ficha de SmartBuds AI en Google Play

Textos e imágenes listos para pegar en Play Console → *Presencia en la tienda → Ficha principal*.

## Imágenes

| Qué | Archivo | Tamaño |
|---|---|---|
| Ícono de la app | `docs/play-store/icono-512.png` | 512 × 512 |
| Gráfico destacado | `docs/play-store/grafico-destacado-1024x500.png` | 1024 × 500 |
| Capturas de pantalla | Tómalas en el teléfono: Inicio, Asistente, Mi música | mínimo 2 |

## Nombre (máx. 30)

SmartBuds AI: música por voz

## Descripción breve (máx. 80)

Di «Cambia» y pasa la canción. Controla tu música sin tocar el teléfono.

## Descripción completa

SmartBuds AI te deja controlar tu música con la voz, con la pantalla apagada y el teléfono en el bolsillo.

**Manos libres**
- «Cambia», «Devuelve», «Pausa», «Continúa», «Sube», «Baja».
- «Busca» y dices la canción: empieza a sonar en tu reproductor.
- «Oye música» y pide lo que quieras.
- Dos toques al audífono para pasar la canción, tres para volver.

**Aprende tus gustos**
- Nota qué canciones escuchas completas, cuáles saltas y cuáles repites.
- «Pon algo que me guste» elige de tus favoritas según la hora del día.
- «Pon algo nuevo» te descubre artistas parecidos a los que más escuchas.
- «Pon algo para entrenar», «algo tranquilo», «de fiesta», «para dormir».

**Privado**
- El reconocimiento de voz funciona dentro del teléfono, sin enviar tu voz a internet.
- «Solo mi voz»: SmartBuds aprende cómo suenas y no obedece a otras personas.
- Cuenta opcional para no perder tus gustos al cambiar de teléfono.

Funciona con YouTube Music y otros reproductores que muestran sus controles en la notificación.

## Categoría y etiquetas

- Categoría: Música y audio
- Etiquetas: control por voz, audífonos, música, manos libres

## Permisos que hay que justificar en Play Console

| Permiso | Para qué se usa |
|---|---|
| Micrófono | Escuchar las órdenes de voz. El audio se procesa en el teléfono. |
| Servicio en primer plano (micrófono) | Seguir escuchando con la pantalla apagada; se muestra una notificación permanente con botón «Detener». |
| Acceso a notificaciones | Saber qué canción suena y controlar el reproductor (siguiente, pausa…). |
| Notificaciones | Mostrar el aviso «SmartBuds está escuchando». |

## Antes de enviar

1. Cambia la clave de YouTube por una nueva y restringida a la app (Google Cloud → Credenciales → restringir por paquete Android y huella SHA-1).
2. Publica `docs/politica-de-privacidad.md` en una página web (por ejemplo, GitHub Pages) y pega el enlace en la ficha.
3. Sigue `docs/publicacion-play-store.md` para crear la firma (keystore) y generar el `.aab`.
