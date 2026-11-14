# Volumen estable mientras Jarvis escucha (PR #38)

## Causa raíz

| Plataforma | Qué pasaba | Por qué |
|---|---|---|
| iPhone | La música subía y bajaba al hablar o cantar. | Cada frase reinicia el reconocimiento, y cada reinicio volvía a fijar la categoría de audio (`playAndRecord`) y a activar la sesión. Eso genera un aviso de **cambio de ruta** (`categoryChange`) y de **configuración del motor**; desde el PR #34 esos avisos reiniciaban la escucha… que volvía a fijar la categoría. **Bucle**: la salida de audio se reconfiguraba sin parar. |
| Android | El volumen subía y bajaba con la conversación o el canto. | El reconocedor sin internet (Vosk) con gramática elige la orden más parecida a lo que oye: hablando o cantando podía «oír» **«sube»** y **«baja»** y SmartBuds los obedecía (volumen del sistema). Además, dos transiciones suaves seguidas («cambia» mal oído) podían pisarse. Escuchar **no** pide foco de audio (Vosk solo graba), así que no había atenuación del sistema. |
| Web | En Chrome para Android, el propio navegador puede pausar o bajar la música al abrir el micrófono. | Lo decide el navegador; la página no lo puede cambiar. En computador no pasa. |

## Configuración antes y después

**iPhone**
- Antes: `setCategory(.playAndRecord, .default, [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])` + `setActive(true)` en **cada** frase; cualquier cambio de ruta o del motor reiniciaba la escucha.
- Después: la misma categoría (sin `.duckOthers`), pero **solo se fija si cambió** y la sesión se activa **una vez**. Solo se reabre la escucha cuando cambia el aparato (audífonos conectados/quitados: `newDeviceAvailable` / `oldDeviceUnavailable`) o si el motor realmente se detuvo. Freno anti-ciclos: más de 4 reinicios automáticos en 15 s se ignoran (el vigilante de Dart la reabre si queda caída).
- Opcional (apagado por defecto): «Bajar la música cuando Jarvis responde» añade `.duckOthers` solo mientras habla y luego desactiva la sesión una vez para devolver el volumen.

**Android**
- Escucha: sin solicitudes de foco de audio (igual que antes). Una sola palabra («sube», «baja», «cambia»…) ahora exige confianza ≥ 0,85 (frases: 0,6).
- Respuesta hablada: solo con el ajuste activado se pide `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` (uso «asistente») mientras habla y se suelta al terminar.

**Dart (ambas)**
- «sube» y «baja» de una sola palabra, contrarios y con menos de 10 s de diferencia: el segundo se ignora y queda en el registro. La frase completa («baja el volumen») siempre funciona.
- Las transiciones suaves nunca se superponen y siempre devuelven el volumen que tenías.
- Los avisos de audio del teléfono (ruta, motor, interrupciones, foco, atenuación) quedan en el registro de Autodiagnóstico.

## Límites del sistema
- Spotify, YouTube Music, etc. pueden tener su propia normalización de volumen: SmartBuds no la controla.
- Una llamada, Siri o una alarma interrumpen el audio (lo decide el sistema); al terminar Jarvis vuelve a escuchar.
- Algunos audífonos Bluetooth cambian de calidad al usar el micrófono del audífono; SmartBuds usa el micrófono sin pedir el modo de llamada.

## Pruebas en el teléfono (con música sonando y Jarvis escuchando)
Marca ✅/❌: 1) silencio 3 min · 2) hablar normal · 3) cantar encima · 4) conversación entre varias personas · 5) dar órdenes · 6) Jarvis respondiendo (con el ajuste apagado y encendido) · 7) conectar y desconectar audífonos · 8) altavoz ↔ audífonos · 9) cambiar de canción · 10) música de Spotify / YouTube Music · 11) música desde SmartBuds · 12) apagar y encender la escucha. Si algo cambia el volumen, abre Privacidad → Autodiagnóstico → «Lo que pasó con la escucha» y anota la línea.
