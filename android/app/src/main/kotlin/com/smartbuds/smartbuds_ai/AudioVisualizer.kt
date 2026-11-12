package com.smartbuds.smartbuds_ai

import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Visualizador que responde al audio real que suena en el teléfono (cualquier
 * app), usando el Visualizer de Android sobre la salida general (sesión 0).
 *
 * Necesita el permiso de micrófono (ya lo tiene SmartBuds por la voz). Algunos
 * fabricantes lo bloquean: en ese caso avisa «unavailable» y la app muestra
 * el ecualizador animado normal.
 */
class AudioVisualizer(private val context: Context, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {

    private val channel = EventChannel(messenger, "smartbuds/visualizer")
    private val main = Handler(Looper.getMainLooper())
    private var visualizer: Visualizer? = null
    private var sink: EventChannel.EventSink? = null

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    private fun start() {
        if (context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            sink?.success(mapOf("unavailable" to "permission"))
            return
        }
        try {
            val v = Visualizer(0)
            v.captureSize = Visualizer.getCaptureSizeRange()[0].coerceAtLeast(256)
            val rate = min(Visualizer.getMaxCaptureRate() / 2, 20000) // ~10–20 por segundo
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(vis: Visualizer?, waveform: ByteArray?, samplingRate: Int) {}
                override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null) return
                    val bands = bands(fft, 16)
                    main.post { sink?.success(mapOf("bands" to bands)) }
                }
            }, rate, false, true)
            v.enabled = true
            visualizer = v
        } catch (e: Throwable) {
            stop()
            sink?.success(mapOf("unavailable" to (e.message ?: "error")))
        }
    }

    private fun stop() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Throwable) {}
        visualizer = null
    }

    /** Agrupa el espectro en [n] bandas (escala logarítmica) con valores 0–1. */
    private fun bands(fft: ByteArray, n: Int): List<Double> {
        val bins = fft.size / 2
        val out = MutableList(n) { 0.0 }
        for (b in 0 until n) {
            val from = max(1, (Math.pow(bins.toDouble(), b.toDouble() / n)).toInt())
            val to = max(from + 1, min(bins, (Math.pow(bins.toDouble(), (b + 1).toDouble() / n)).toInt()))
            var sum = 0.0
            for (i in from until to) {
                val re = fft[2 * i].toDouble()
                val im = fft[2 * i + 1].toDouble()
                sum += hypot(re, im)
            }
            val avg = sum / (to - from)
            out[b] = (ln(1 + avg) / ln(1 + 128.0)).coerceIn(0.0, 1.0)
        }
        return out
    }
}
