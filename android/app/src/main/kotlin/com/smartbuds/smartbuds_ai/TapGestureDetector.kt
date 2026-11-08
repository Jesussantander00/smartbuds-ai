package com.smartbuds.smartbuds_ai

import android.content.Context
import android.media.session.MediaController
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Toques en el botón de los audífonos, sin permisos especiales.
 *
 * Los audífonos sencillos solo envían «play/pausa». SmartBuds observa el
 * reproductor: si en menos de medio segundo pasa de sonar → pausa → sonar
 * (dos toques), salta a la siguiente; con tres toques (sonar → pausa →
 * sonar → pausa) vuelve a la anterior y sigue sonando.
 *
 * Los audífonos que ya mandan «siguiente» con dos toques no pasan por aquí
 * (el reproductor salta directamente), así que no hay saltos dobles.
 */
class TapGestureDetector(context: Context) {

    companion object {
        private const val PREFS = "smartbuds"
        private const val KEY_ENABLED = "tap_gestures"

        /** Tiempo máximo entre un toque y el siguiente. */
        private const val TAP_GAP_MS = 600L
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())

    /** Último estado (sonando/pausa) de cada reproductor. */
    private val lastState = mutableMapOf<String, Int>()
    private val toggles = mutableListOf<Int>()
    private var lastToggleAt = 0L
    private var suppressUntil = 0L
    private var pending: Runnable? = null

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) {
            prefs.edit().putBoolean(KEY_ENABLED, value).apply()
            if (!value) reset()
        }

    /** Ignora cambios causados por SmartBuds mismo (órdenes de voz). */
    fun suppress(ms: Long = 1500) {
        suppressUntil = SystemClock.elapsedRealtime() + ms
        reset()
    }

    fun onState(controller: MediaController, state: PlaybackState?) {
        val s = state?.state ?: return
        // Solo cuentan «sonando» y «en pausa»; cargando, saltando, etc. se ignoran.
        if (s != PlaybackState.STATE_PLAYING && s != PlaybackState.STATE_PAUSED) return
        val id = controller.packageName
        val previous = lastState.put(id, s)
        if (previous == null || previous == s || !enabled) return

        val now = SystemClock.elapsedRealtime()
        if (now < suppressUntil) return
        if (toggles.isNotEmpty() && now - lastToggleAt > TAP_GAP_MS) toggles.clear()
        // Un gesto siempre empieza pausando lo que sonaba.
        if (toggles.isEmpty() && s != PlaybackState.STATE_PAUSED) return
        toggles += s
        lastToggleAt = now

        pending?.let(main::removeCallbacks)
        val check = Runnable { finish(controller) }
        pending = check
        main.postDelayed(check, TAP_GAP_MS)
    }

    private fun finish(controller: MediaController) {
        val taps = toggles.size
        val last = toggles.lastOrNull()
        reset()
        val controls = controller.transportControls
        when {
            taps == 2 && last == PlaybackState.STATE_PLAYING -> {
                suppress()
                controls.skipToNext()
            }
            taps == 3 && last == PlaybackState.STATE_PAUSED -> {
                suppress()
                controls.skipToPrevious()
                controls.play()
            }
        }
    }

    private fun reset() {
        pending?.let(main::removeCallbacks)
        pending = null
        toggles.clear()
    }
}
