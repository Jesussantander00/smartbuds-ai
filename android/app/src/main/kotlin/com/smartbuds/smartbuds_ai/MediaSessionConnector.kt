package com.smartbuds.smartbuds_ai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Active Player Detector (lado Android).
 *
 * - NotificationListenerService: autorización del usuario.
 * - MediaSessionManager: sesiones multimedia activas.
 * - MediaController: estado, metadatos y acciones disponibles.
 * - TransportControls: envío de comandos estándar.
 */
class MediaSessionConnector(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        var instance: MediaSessionConnector? = null
            private set
    }

    private val main = Handler(Looper.getMainLooper())
    private val sessionManager =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val listenerComponent =
        ComponentName(context, SmartBudsNotificationListener::class.java)

    private val methodChannel = MethodChannel(messenger, "smartbuds/media")
    private val eventChannel = EventChannel(messenger, "smartbuds/media/events")
    private var sink: EventChannel.EventSink? = null

    /** Controladores observados, por playerId. */
    private val watched = mutableMapOf<String, Pair<MediaController, MediaController.Callback>>()
    private var sessionsListenerRegistered = false

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
            rewatch(controllers ?: emptyList())
            emit()
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        instance = this
    }

    fun dispose() {
        stopWatching()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (instance === this) instance = null
    }

    fun onListenerConnected() = main.post {
        if (sink != null) startWatching()
        emit()
    }

    // ---------------------------------------------------------------- Métodos

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "openNotificationAccessSettings" -> {
                    openNotificationAccessSettings(); result.success(null)
                }
                "getSessions" -> result.success(activeControllers().map(::toMap))
                "getSession" -> {
                    val id = call.argument<String>("playerId")
                    result.success(findController(id)?.let(::toMap))
                }
                "sendCommand" -> result.success(
                    sendCommand(call.argument("playerId"), call.argument("command"))
                )
                "adjustSystemVolume" -> result.success(
                    adjustVolume(call.argument<String>("direction") == "up")
                )
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            // Acceso a notificaciones revocado mientras la app estaba abierta.
            result.error("PERMISSION", e.message, null)
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it) == listenerComponent
        }
    }

    private fun openNotificationAccessSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                listenerComponent.flattenToString()
            )
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /** En el orden de prioridad que da el sistema. */
    private fun activeControllers(): List<MediaController> =
        if (!hasNotificationAccess()) emptyList()
        else sessionManager.getActiveSessions(listenerComponent)

    private fun playerId(c: MediaController) =
        "${c.packageName}#${c.sessionToken.hashCode()}"

    private fun findController(id: String?): MediaController? =
        id?.let { target -> activeControllers().firstOrNull { playerId(it) == target } }

    private fun sendCommand(id: String?, command: String?): Boolean {
        val c = findController(id) ?: return false
        val t = c.transportControls
        val state = c.playbackState?.state
        when (command) {
            "play" -> t.play()
            "pause" -> t.pause()
            "togglePlayPause" ->
                if (state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
            "next" -> t.skipToNext()
            "previous" -> t.skipToPrevious()
            "volumeUp" -> c.adjustVolume(AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
            "volumeDown" -> c.adjustVolume(AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
            else -> return false
        }
        return true
    }

    private fun adjustVolume(up: Boolean): Boolean {
        audioManager.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
            AudioManager.FLAG_SHOW_UI
        )
        return true
    }

    // ------------------------------------------------------------- Conversión

    private fun toMap(c: MediaController): Map<String, Any?> {
        val ps = c.playbackState
        val md = c.metadata
        return mapOf(
            "playerId" to playerId(c),
            "packageName" to c.packageName,
            "appName" to appLabel(c.packageName),
            "state" to stateName(ps?.state),
            "title" to md?.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to (md?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: md?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)),
            "positionMs" to ps?.let { currentPosition(it) },
            "lastActiveAtMs" to ps?.let { toEpochMs(it.lastPositionUpdateTime) },
            "actions" to actions(ps),
        )
    }

    private fun stateName(state: Int?) = when (state) {
        PlaybackState.STATE_PLAYING -> "playing"
        PlaybackState.STATE_PAUSED -> "paused"
        PlaybackState.STATE_STOPPED, PlaybackState.STATE_NONE -> "stopped"
        PlaybackState.STATE_BUFFERING, PlaybackState.STATE_CONNECTING,
        PlaybackState.STATE_SKIPPING_TO_NEXT, PlaybackState.STATE_SKIPPING_TO_PREVIOUS,
        PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM -> "buffering"
        else -> "unknown"
    }

    /** Traduce las acciones que la sesión declara a comandos universales. */
    private fun actions(ps: PlaybackState?): List<String> {
        val a = ps?.actions ?: 0L
        fun has(flag: Long) = (a and flag) != 0L
        val out = mutableListOf<String>()
        val canPlay = has(PlaybackState.ACTION_PLAY) || has(PlaybackState.ACTION_PLAY_PAUSE)
        val canPause = has(PlaybackState.ACTION_PAUSE) || has(PlaybackState.ACTION_PLAY_PAUSE)
        if (canPlay) out += "play"
        if (canPause) out += "pause"
        if (canPlay && canPause) out += "togglePlayPause"
        if (has(PlaybackState.ACTION_SKIP_TO_NEXT)) out += "next"
        if (has(PlaybackState.ACTION_SKIP_TO_PREVIOUS)) out += "previous"
        // El volumen de la sesión siempre se puede pedir al sistema.
        out += listOf("volumeUp", "volumeDown")
        return out
    }

    private fun currentPosition(ps: PlaybackState): Long {
        if (ps.state != PlaybackState.STATE_PLAYING) return ps.position
        val elapsed = SystemClock.elapsedRealtime() - ps.lastPositionUpdateTime
        return ps.position + (elapsed * ps.playbackSpeed).toLong()
    }

    /** lastPositionUpdateTime usa elapsedRealtime; lo pasamos a epoch. */
    private fun toEpochMs(elapsedRealtimeMs: Long): Long =
        if (elapsedRealtimeMs <= 0L) 0L
        else System.currentTimeMillis() - (SystemClock.elapsedRealtime() - elapsedRealtimeMs)

    private fun appLabel(pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        pkg
    }

    // ----------------------------------------------------------------- Eventos

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        startWatching()
        emit()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        stopWatching()
    }

    private fun startWatching() {
        if (!hasNotificationAccess()) return
        try {
            if (!sessionsListenerRegistered) {
                sessionManager.addOnActiveSessionsChangedListener(
                    sessionsListener, listenerComponent, main
                )
                sessionsListenerRegistered = true
            }
            rewatch(activeControllers())
        } catch (_: SecurityException) {
            sessionsListenerRegistered = false
        }
    }

    private fun stopWatching() {
        if (sessionsListenerRegistered) {
            sessionManager.removeOnActiveSessionsChangedListener(sessionsListener)
            sessionsListenerRegistered = false
        }
        watched.values.forEach { (c, cb) -> c.unregisterCallback(cb) }
        watched.clear()
    }

    /** Observa estado y metadatos de cada sesión para avisar a Flutter. */
    private fun rewatch(controllers: List<MediaController>) {
        val ids = controllers.map(::playerId).toSet()
        watched.keys.filter { it !in ids }.forEach { id ->
            watched.remove(id)?.let { (c, cb) -> c.unregisterCallback(cb) }
        }
        controllers.forEach { c ->
            val id = playerId(c)
            if (id in watched) return@forEach
            val cb = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
                override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
                override fun onSessionDestroyed() {
                    watched.remove(id)?.let { (ctrl, callback) ->
                        ctrl.unregisterCallback(callback)
                    }
                    emit()
                }
            }
            c.registerCallback(cb, main)
            watched[id] = c to cb
        }
    }

    private fun emit() {
        val s = sink ?: return
        val payload = try {
            activeControllers().map(::toMap)
        } catch (_: SecurityException) {
            emptyList()
        }
        main.post { s.success(payload) }
    }
}
