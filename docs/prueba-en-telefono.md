# Prueba en un teléfono real

Antes de agregar funciones nuevas: comprobar que el cerebro musical (#18, #23),
la experiencia inmersiva (#19, #23), las herramientas de audio (#21) y el
ecosistema multidispositivo (#22) funcionan juntos en un teléfono de verdad.

Marca cada punto con ✅ (funciona), ⚠️ (raro) o ❌ (falla) y anota qué pasó.

## Preparación

- [ ] `git pull` en el PC y `flutter run --dart-define-from-file=secrets.json` en el teléfono (Android) o el emulador.
- [ ] **Cuenta A (nueva):** recién creada, sin historial.
- [ ] **Cuenta B (con historial):** la que más has usado (o escucha ~30 canciones antes de probar).
- [ ] Ten al menos 2 apps de música instaladas (p. ej. Spotify y YouTube Music).

## 1. Cerebro musical — cuenta A (nueva)

- [ ] Inicio → «Para ti ahora» dice «Todavía estoy aprendiendo: llevo X de 20 canciones».
- [ ] Di «pon algo que me guste»: si recomienda, avisa que aún te está conociendo; si no tiene nada, lo dice sin inventar.
- [ ] Escucha 20 canciones: el aviso desaparece.

## 2. Cerebro musical — cuenta B (con historial)

- [ ] «Para ti ahora» muestra 5–6 sugerencias de **artistas distintos** (no 3 del mismo).
- [ ] Cada razón muestra un dato real («La terminaste 9 de 11 veces», «Hace 30 días no suena»…). Compara con Mi música: ¿cuadra?
- [ ] Salta **una vez** una favorita: sigue apareciendo en sugerencias más tarde.
- [ ] Sáltala **dos veces más**: deja de aparecer.
- [ ] Toca una sugerencia: suena en tu app de música. Termínala o sáltala; repite varias veces: ¿mejoran las sugerencias?
- [ ] «Estoy nostálgico» / «me siento con energía»: responde con música acorde.

## 3. Experiencia inmersiva

- [ ] Toca la carátula: abre a pantalla completa; desliza hacia abajo para salir. Entra y sal 5 veces: sin saltos ni pantallas negras.
- [ ] El fondo toma el color de la carátula.
- [ ] Visualizador: ¿las barras siguen la música real? (si tu teléfono lo bloquea, debe verse la animación normal, no barras quietas).
- [ ] Pausa 5 s: las barras vuelven a la animación normal.
- [ ] Ajustes del teléfono → Accesibilidad → **quitar animaciones**: la carátula deja de «respirar» y las barras quedan quietas.
- [ ] Prueba con Spotify y con YouTube Music.

## 4. Batería y temperatura (sesión larga)

- [ ] Anota la batería, deja el modo inmersivo 30 min con música: ¿cuánto bajó? ¿se calienta el teléfono?
- [ ] Repite 30 min con la pantalla apagada (solo voz).
- [ ] Con batería ≤ 20 % y «Ahorro de batería» de SmartBuds activado: se apagan carátula viva y visualizador.

## 5. Herramientas de audio

- [ ] Dispositivos → Herramientas de audio → «Abrir el ecualizador del teléfono» abre el de tu marca (o avisa que no hay).
- [ ] «Calidad de la salida» muestra datos al cambiar entre parlante y audífonos (toca Actualizar).
- [ ] Transiciones suaves activadas: «Cambia» baja y sube el volumen.
- [ ] Límite de volumen en 60 %: «volumen al máximo» se queda en 60 % y lo dice.
- [ ] Mi música → Análisis de reproducción: las sesiones y los minutos cuadran con lo que escuchaste.

## 6. Multidispositivo (dos teléfonos, misma cuenta)

- [ ] Dispositivos → Centro multidispositivo en ambos: cada uno ve al otro con lo que suena y «en línea».
- [ ] «Continuar aquí» pone la misma canción en este teléfono.
- [ ] Modo privado en uno: el otro ya no ve lo que suena.
- [ ] Marca el Bluetooth del carro (o unos audífonos para probar): al conectarlo se abre el modo carro. «Sal del modo carro» lo cierra.
- [ ] La notificación de SmartBuds trae «Me gusta» y guarda la canción.

## 7. Social (tres cuentas, si puedes)

- [ ] Agregar amigos por código, enviar canción, lista compartida con votos, escuchar juntos.

## Resultado

Anota aquí lo que falló y pégalo en el chat: eso decide el próximo PR.
