# SmartBuds como centro musical multiplataforma (PR #45)

```
SmartBuds AI
├─ Buscador musical unificado   (lib/features/player/catalog.dart → MusicCatalog)
│    búsqueda, álbumes, sin duplicados, disponibilidad y prioridad configurable
├─ Proveedores (adaptadores)    (InAppCatalog: YouTube, Audius, Deezer, Apple/iTunes)
│    cada uno declara sus capacidades reales (ProviderRegistry)
├─ Reproductor central          (SmartBudsPlayer: una sola cola, un estado, controles)
│    motores: YouTubeEngine (IFrame oficial) y NativeAudioEngine (MediaPlayer / AVPlayer)
└─ Jarvis                       (habla con el reproductor central, nunca con cada proveedor)
```

**Buscar no es reproducir.** Cada proveedor declara qué permite; solo lo reproducible se ofrece como reproducible.

## Auditoría (noviembre 2026)

| Plataforma | Buscar | Álbumes / artistas | Portadas y datos | Reproducción dentro de una app de terceros | Necesita | Android | iPhone | Web | En SmartBuds |
|---|---|---|---|---|---|---|---|---|---|
| **YouTube** | Sí (Data API) | No (solo videos/canales) | Sí | **Completa** con el reproductor oficial incrustado (video visible, sin segundo plano) | Clave de API (quien instala) | Sí | Sí | Sí | **Integrado** |
| **YouTube Music** | — | — | — | No tiene API pública propia | — | — | — | — | Se usa el catálogo de YouTube |
| **Audius** | Sí | Sí | Sí | **Completa** (API pública, `app_name`) | Nada | Sí | Sí | No integrado aún | **Integrado** |
| **Deezer** | Sí | Sí | Sí | Solo **30 s** (vista previa oficial) | Nada | Sí | Sí | No (su API no permite llamadas desde el navegador) | **Integrado** (vista previa) |
| **Apple (iTunes Search)** | Sí | Sí | Sí | Solo **30 s** | Nada | Sí | Sí | No integrado aún | **Integrado** (vista previa) |
| **Apple Music (MusicKit)** | Sí | Sí | Sí | Completa **solo con suscripción** y MusicKit | Cuenta de desarrollador de pago + suscripción del usuario | SDK propio | ApplicationMusicPlayer | MusicKit JS | **No** (no hay cuenta de desarrollador) |
| **Spotify** | Sí (con app registrada) | Sí | Sí | **No dentro de otra app**: App Remote controla la app de Spotify; Web Playback SDK solo web y Premium. Desde nov. 2024 las apps nuevas no reciben vistas previas | App registrada + autorización; Premium para reproducir | No | No | Solo Premium | **No** |
| **SoundCloud** | Sí | Sí | Sí | Completa con su API oficial (stream) o su reproductor incrustado | App registrada (registro a veces cerrado) + servidor que guarde la clave secreta | Con servidor | Con servidor | Reproductor incrustado | **No** (no hay credenciales ni servidor) |

La misma tabla está en la app: **Asistente → Música → Fuentes musicales**.

## Buscador unificado
- Consulta en paralelo los proveedores integrados, intercala sus resultados y **une duplicados** («Artista - Canción (Video oficial)», «feat.», «- Topic», «VEVO»…): una fila por canción con todas sus fuentes.
- Cada fila: título, artista, álbum, portada, duración, fuentes y disponibilidad («Completa en SmartBuds» / «Solo vista previa de 30 s»).
- Orden: lo que coincide con lo buscado (título, artista o álbum) → lo que se escucha completo → relevancia del proveedor. Audius que no tiene nada que ver con lo pedido se descarta (no se finge).
- **Prioridad configurable** entre fuentes completas (Fuentes musicales); las vistas previas siempre después.
- Álbumes (Deezer y Apple): tocar un álbum pone la primera canción y deja el resto en la cola; cada una se resuelve al sonar (completa si alguna fuente la tiene).

## Nunca sale de SmartBuds solo
- Si ninguna fuente integrada tiene la canción, Jarvis lo dice y abre los resultados. Solo el botón «Buscarla en mi app de música (sale de SmartBuds)» abre otra app, porque lo tocas tú. Decir «… en Spotify» también es un pedido explícito.

## Jarvis
«Busca música de Shakira» · «Reproduce la primera / segunda canción» · «Busca otra versión» · «Agrega esta canción a la cola» · «Pausa» · «Continúa» · «Sube el volumen» (del reproductor) · «Otra del mismo artista» · «Pon el álbum …».

## Pruebas en el teléfono
1. Escribe «Shakira» en Buscar: resultados con sus fuentes; toca uno y suena en la barra de SmartBuds.
2. Busca un álbum («Pies Descalzos»): tócalo en la fila de álbumes.
3. Busca una canción que solo tenga vista previa: dice «Vista previa 30 s».
4. Cambia la prioridad en Fuentes musicales y repite.
5. Por voz: «busca música de Shakira», «reproduce la segunda», «busca otra versión», «agrega esta canción a la cola», «pausa», «continúa», «sube el volumen», «otra del mismo artista».
6. Busca algo inexistente: SmartBuds no abre ninguna app.
