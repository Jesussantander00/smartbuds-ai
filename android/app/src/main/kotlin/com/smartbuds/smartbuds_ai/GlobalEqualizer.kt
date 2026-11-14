package com.smartbuds.smartbuds_ai

import android.media.audiofx.Equalizer

/**
 * Ecualizador sobre la salida general del teléfono (sesión 0).
 *
 * Límite honesto: Android marcó la sesión 0 como obsoleta y muchos fabricantes
 * la ignoran o la bloquean. Por eso [apply] lee de vuelta las bandas y dice si
 * de verdad quedó aplicado; si no, SmartBuds muestra los valores recomendados
 * para el ecualizador del teléfono.
 */
object GlobalEqualizer {
    private var eq: Equalizer? = null

    private fun instance(): Equalizer? {
        eq?.let { return it }
        return try {
            Equalizer(0, 0).also { eq = it }
        } catch (_: Throwable) {
            null
        }
    }

    /** Bandas (frecuencia central en Hz) y rango en milibelios, o available=false. */
    fun info(): Map<String, Any> {
        val e = instance() ?: return mapOf("available" to false)
        return try {
            val bands = e.numberOfBands.toInt()
            val range = e.bandLevelRange
            mapOf(
                "available" to true,
                "bands" to (0 until bands).map { e.getCenterFreq(it.toShort()) / 1000 },
                "min" to range[0].toInt(),
                "max" to range[1].toInt(),
                "enabled" to e.enabled,
            )
        } catch (_: Throwable) {
            mapOf("available" to false)
        }
    }

    /** Aplica niveles (milibelios, uno por banda). Devuelve true si se leyeron igual. */
    fun apply(levels: List<Int>): Boolean {
        val e = instance() ?: return false
        return try {
            val range = e.bandLevelRange
            val n = minOf(levels.size, e.numberOfBands.toInt())
            for (i in 0 until n) {
                val v = levels[i].coerceIn(range[0].toInt(), range[1].toInt())
                e.setBandLevel(i.toShort(), v.toShort())
            }
            e.enabled = true
            (0 until n).all { i ->
                val want = levels[i].coerceIn(range[0].toInt(), range[1].toInt())
                kotlin.math.abs(e.getBandLevel(i.toShort()) - want) <= 100
            } && e.enabled
        } catch (_: Throwable) {
            false
        }
    }

    fun release() {
        try {
            eq?.enabled = false
            eq?.release()
        } catch (_: Throwable) {
        }
        eq = null
    }
}
