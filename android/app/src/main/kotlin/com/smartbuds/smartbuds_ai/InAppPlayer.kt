package com.smartbuds.smartbuds_ai

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reproductor propio de SmartBuds: reproduce audio por URL (streams de catálogos
 * que lo permiten, como Audius) dentro de la app, sin abrir otra aplicación.
 * La cola y la lógica de «siguiente» viven en Dart (SmartBudsPlayer).
 */
class InAppPlayer(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, "smartbuds/player")
    private val eventChannel = EventChannel(messenger, "smartbuds/player/events")
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var sink: EventChannel.EventSink? = null

    private var player: MediaPlayer? = null
    private var state = "stopped"
    private var title: String? = null
    private var artist: String? = null
    private var lastActiveAt = 0L
    private var focusRequest: AudioFocusRequest? = null
    private var volume = 1f

    /** Mientras suena, avisa la posición cada segundo (barra de progreso). */
    private val ticker = object : Runnable {
        override fun run() {
            if (state == "playing") {
                emit("state", statusMap())
                main.postDelayed(this, 1000)
            }
        }
    }

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    /** Si otra app toma el audio (llamada, otro reproductor), SmartBuds pausa. */
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> pause()
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        release()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                play(
                    call.argument<String>("url") ?: return result.error("ARG", "url", null),
                    call.argument("title"),
                    call.argument("artist"),
                )
                result.success(true)
            }
            "pause" -> { pause(); result.success(true) }
            "resume" -> { resume(); result.success(true) }
            "stop" -> { release(); setState("stopped"); result.success(true) }
            "seek" -> {
                val ms = call.argument<Number>("positionMs")?.toInt() ?: 0
                try { player?.seekTo(ms) } catch (_: Exception) {}
                emit("state", statusMap())
                result.success(true)
            }
            "setVolume" -> {
                // Volumen del reproductor de SmartBuds (no el del teléfono).
                volume = ((call.argument<Number>("percent")?.toFloat() ?: 100f) / 100f).coerceIn(0f, 1f)
                try { player?.setVolume(volume, volume) } catch (_: Exception) {}
                result.success(true)
            }
            "status" -> result.success(statusMap())
            else -> result.notImplemented()
        }
    }

    private fun play(url: String, newTitle: String?, newArtist: String?) {
        release()
        title = newTitle
        artist = newArtist
        if (!requestFocus()) {
            setState("paused")
            return
        }
        setState("buffering")
        val mp = MediaPlayer()
        player = mp
        try {
            mp.setAudioAttributes(attributes)
            mp.setDataSource(url)
            mp.setOnPreparedListener {
                it.setVolume(volume, volume)
                it.start()
                setState("playing")
            }
            mp.setOnCompletionListener { setState("completed") }
            mp.setOnErrorListener { _, what, extra ->
                emit("error", mapOf("message" to "No se pudo reproducir ($what/$extra)"))
                setState("stopped")
                true
            }
            mp.prepareAsync()
        } catch (e: Exception) {
            emit("error", mapOf("message" to (e.message ?: "Error al reproducir")))
            setState("stopped")
        }
    }

    private fun pause() {
        val mp = player ?: return
        if (mp.isPlaying) mp.pause()
        setState("paused")
    }

    private fun resume() {
        val mp = player ?: return
        if (state == "paused" && requestFocus()) {
            mp.start()
            setState("playing")
        }
    }

    private fun release() {
        player?.setOnCompletionListener(null)
        player?.release()
        player = null
        abandonFocus()
    }

    private fun requestFocus(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, main)
                .build()
            focusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN
            )
        }
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun setState(newState: String) {
        state = newState
        lastActiveAt = System.currentTimeMillis()
        emit("state", statusMap())
        main.removeCallbacks(ticker)
        if (newState == "playing") main.postDelayed(ticker, 1000)
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "state" to state,
        "title" to title,
        "artist" to artist,
        "positionMs" to (try { player?.currentPosition?.toLong() } catch (_: Exception) { null }),
        "durationMs" to (try {
            if (state == "playing" || state == "paused") player?.duration?.toLong()?.takeIf { it > 0 } else null
        } catch (_: Exception) { null }),
        "lastActiveAtMs" to lastActiveAt,
    )

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(type: String, data: Map<String, Any?>) {
        val payload = HashMap<String, Any?>(data)
        payload["type"] = type
        main.post { sink?.success(payload) }
    }
}
