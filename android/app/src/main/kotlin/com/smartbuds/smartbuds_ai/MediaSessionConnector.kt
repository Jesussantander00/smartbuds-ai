package com.smartbuds.smartbuds_ai

import android.app.SearchManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.BatteryManager
import java.io.ByteArrayOutputStream
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
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

    /** Dos/tres toques en el botón de los audífonos. */
    val taps = TapGestureDetector(context)

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
        stopCallWatch()
        setPauseOnUnplug(false)
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
                "playFromSearch" -> result.success(
                    playFromSearch(
                        call.argument<String>("packageName"),
                        call.argument<String>("query") ?: "",
                        call.argument<String>("mode") ?: "auto"
                    )
                )
                "playUriInSession" -> result.success(
                    playUriInSession(
                        call.argument("packageName"),
                        call.argument("uri"),
                        call.argument("mediaId")
                    )
                )
                "openUri" -> result.success(
                    openUri(call.argument("uri"), call.argument("packageName"))
                )
                "filesDir" -> result.success(context.filesDir.absolutePath)
                "bringToFront" -> {
                    bringToFront(); result.success(null)
                }
                "seek" -> result.success(
                    seek(
                        call.argument("playerId"),
                        call.argument<Number>("positionMs")?.toLong(),
                        call.argument<Number>("deltaMs")?.toLong(),
                    )
                )
                "shareText" -> result.success(shareText(call.argument<String>("text") ?: ""))
                "setTapGestures" -> {
                    taps.enabled = call.argument<Boolean>("enabled") != false
                    result.success(true)
                }
                "setVolumePercent" -> result.success(
                    setVolumePercent(call.argument<Number>("percent")?.toInt() ?: 50)
                )
                "getVolumePercent" -> result.success(volumePercent())
                "getOutputDevice" -> result.success(outputDevice())
                "getBattery" -> result.success(battery())
                "setCallPause" -> {
                    callPauseEnabled = call.argument<Boolean>("enabled") != false
                    if (callPauseEnabled) startCallWatch() else stopCallWatch()
                    result.success(true)
                }
                "setPauseOnUnplug" -> {
                    setPauseOnUnplug(call.argument<Boolean>("enabled") != false)
                    result.success(true)
                }
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
        taps.suppress() // la orden de voz no cuenta como toque
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

    /** Salta a [positionMs] (absoluto) o mueve [deltaMs] desde donde va. */
    private fun seek(id: String?, positionMs: Long?, deltaMs: Long?): Boolean {
        val c = findController(id) ?: return false
        val ps = c.playbackState ?: return false
        if ((ps.actions and PlaybackState.ACTION_SEEK_TO) == 0L) return false
        val target = positionMs ?: (currentPosition(ps) + (deltaMs ?: 0L))
        val duration = c.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        val clamped = if (duration > 2000) target.coerceIn(0L, duration - 1000L) else target.coerceAtLeast(0L)
        taps.suppress()
        c.transportControls.seekTo(clamped)
        return true
    }

    /** Abre el menú «Compartir» de Android con el texto (WhatsApp, etc.). */
    private fun shareText(text: String): Boolean {
        if (text.isBlank()) return false
        return try {
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            val chooser = Intent.createChooser(send, "Compartir canción")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Busca y reproduce en la app indicada.
     * - mode "session": pide playFromSearch a la sesión multimedia activa de esa
     *   app, aunque no declare ACTION_PLAY_FROM_SEARCH (algunas lo aceptan igual).
     * - mode "intent": intención estándar MEDIA_PLAY_FROM_SEARCH (la del Asistente),
     *   indicando que lo buscado es una canción.
     * - mode "auto": sesión si la declara; si no, intención.
     */
    private fun playFromSearch(packageName: String?, query: String, mode: String): Boolean {
        taps.suppress(4000) // cambiar de canción por búsqueda no es un toque
        if (query.isBlank() || packageName.isNullOrBlank()) return false
        val session = activeControllers().firstOrNull { it.packageName == packageName }
        val declares = ((session?.playbackState?.actions ?: 0L) and
            PlaybackState.ACTION_PLAY_FROM_SEARCH) != 0L

        if (mode == "session" || (mode == "auto" && declares)) {
            if (session == null) return false
            session.transportControls.playFromSearch(query, Bundle())
            return true
        }

        val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
            setPackage(packageName)
            putExtra(SearchManager.QUERY, query)
            putExtra(MediaStore.EXTRA_MEDIA_FOCUS, MediaStore.Audio.Media.ENTRY_CONTENT_TYPE)
            putExtra(MediaStore.EXTRA_MEDIA_TITLE, query)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Trae SmartBuds de vuelta al frente sin detener la música del otro reproductor.
     * En Android 10+ el sistema puede bloquearlo si la app lleva tiempo en segundo
     * plano; se hace justo después de la búsqueda, cuando aún está permitido.
     */
    /**
     * Pide a la sesión multimedia de la app que reproduzca un enlace, sin abrir
     * su pantalla (mismo canal invisible que «Cambia»). La app puede ignorarlo;
     * Dart verifica si la canción cambió.
     */
    private fun playUriInSession(packageName: String?, uri: String?, mediaId: String?): Boolean {
        taps.suppress(4000) // cambiar de canción por búsqueda no es un toque
        val session = activeControllers().firstOrNull { it.packageName == packageName }
            ?: return false
        val controls = session.transportControls
        if (!uri.isNullOrBlank()) controls.playFromUri(android.net.Uri.parse(uri), Bundle())
        if (!mediaId.isNullOrBlank()) controls.playFromMediaId(mediaId, Bundle())
        return true
    }

    /** Abre un enlace (p. ej. music.youtube.com/watch?v=…) en la app indicada. */
    private fun openUri(uri: String?, packageName: String?): Boolean {
        taps.suppress(4000) // cambiar de canción por búsqueda no es un toque
        if (uri.isNullOrBlank()) return false
        val intent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(uri)).apply {
            if (!packageName.isNullOrBlank()) setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun bringToFront() {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // Sin permiso para volver al frente: la música sigue igual.
        }
    }

    // ------------------------------------------------- Volumen, salida, batería

    private fun setVolumePercent(percent: Int): Boolean {
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val target = Math.round(max * percent.coerceIn(0, 100) / 100f)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, AudioManager.FLAG_SHOW_UI)
        return true
    }

    private fun volumePercent(): Int {
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0
        return Math.round(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) * 100f / max)
    }

    /** Nombre de los audífonos conectados (Bluetooth o cable), o null. */
    private fun outputDevice(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val wanted = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
        val d = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type in wanted } ?: return null
        val name = d.productName?.toString()?.trim().orEmpty()
        return name.ifEmpty {
            if (d.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) "Audífonos Bluetooth" else "Audífonos con cable"
        }
    }

    private fun battery(): Map<String, Any> {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val charging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) bm.isCharging else false
        return mapOf("level" to level, "charging" to charging)
    }

    // ------------------------------------- Pausa al quitarse los audífonos

    private var noisyRegistered = false
    private val noisyReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                try {
                    activeControllers().filter {
                        it.playbackState?.state == PlaybackState.STATE_PLAYING
                    }.forEach { it.transportControls.pause() }
                } catch (_: SecurityException) {}
            }
        }
    }

    private fun setPauseOnUnplug(enabled: Boolean) {
        if (enabled && !noisyRegistered) {
            context.registerReceiver(
                noisyReceiver,
                android.content.IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            )
            noisyRegistered = true
        } else if (!enabled && noisyRegistered) {
            try { context.unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
            noisyRegistered = false
        }
    }

    // ------------------------------------------- Pausa durante llamadas

    private var callPauseEnabled = false
    private var inCall = false
    private var pausedForCall: String? = null
    private val callWatch = object : Runnable {
        override fun run() {
            val mode = audioManager.mode
            val calling = mode == AudioManager.MODE_IN_CALL ||
                mode == AudioManager.MODE_IN_COMMUNICATION ||
                mode == AudioManager.MODE_RINGTONE
            if (calling && !inCall) {
                inCall = true
                val playing = try {
                    activeControllers().firstOrNull {
                        it.playbackState?.state == PlaybackState.STATE_PLAYING
                    }
                } catch (_: SecurityException) { null }
                if (playing != null) {
                    pausedForCall = playerId(playing)
                    playing.transportControls.pause()
                }
            } else if (!calling && inCall) {
                inCall = false
                val id = pausedForCall
                pausedForCall = null
                if (id != null) main.postDelayed({
                    try { findController(id)?.transportControls?.play() } catch (_: SecurityException) {}
                }, 1500)
            }
            if (callPauseEnabled) main.postDelayed(this, 1500)
        }
    }

    private fun startCallWatch() {
        main.removeCallbacks(callWatch)
        main.post(callWatch)
    }

    private fun stopCallWatch() = main.removeCallbacks(callWatch)

    /** Para los botones de la notificación: actúa sobre lo que está sonando. */
    fun commandActive(command: String): Boolean {
        val list = try { activeControllers() } catch (_: SecurityException) { emptyList() }
        val c = list.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: list.firstOrNull() ?: return false
        return sendCommand(playerId(c), command)
    }

    // ------------------------------------------------------------- Carátula

    private var artKey: String? = null
    private var artBytes: ByteArray? = null

    /** Carátula reducida a 160 px en JPEG, cacheada por canción. */
    private fun artFor(md: MediaMetadata?): ByteArray? {
        if (md == null) return null
        val key = "${md.getString(MediaMetadata.METADATA_KEY_TITLE)}|" +
            "${md.getString(MediaMetadata.METADATA_KEY_ARTIST)}"
        if (key == artKey) return artBytes
        val bmp = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: md.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        artKey = key
        artBytes = try {
            bmp?.let {
                val scaled = Bitmap.createScaledBitmap(it, 160, 160, true)
                val out = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 80, out)
                out.toByteArray()
            }
        } catch (_: Exception) { null }
        return artBytes
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
            "durationMs" to md?.getLong(MediaMetadata.METADATA_KEY_DURATION)?.takeIf { it > 0 },
            "album" to md?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "art" to if (ps?.state == PlaybackState.STATE_PLAYING ||
                ps?.state == PlaybackState.STATE_PAUSED) artFor(md) else null,
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
                override fun onPlaybackStateChanged(state: PlaybackState?) {
                    taps.onState(c, state)
                    emit()
                }
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
