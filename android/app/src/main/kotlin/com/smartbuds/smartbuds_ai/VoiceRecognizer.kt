package com.smartbuds.smartbuds_ai

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.SpeakerModel
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Voice Engine (lado Android).
 *
 * - Escucha continua con Vosk, sin internet y sin pausar la música.
 * - Servicio en primer plano (VoiceForegroundService) para seguir escuchando
 *   con la pantalla apagada.
 * - Respuesta hablada (TextToSpeech); mientras habla, Vosk no escucha.
 * - Escucha precisa de una sola frase con el reconocedor del sistema
 *   («Busca» → «¿Qué canción?» → nombre), mejor para nombres de artistas.
 * - Aviso de audífonos conectados / desconectados (sin permisos extra).
 *
 * El modelo (vosk-model-small-es) va en assets/model-es y se copia a la
 * memoria interna la primera vez. Se descarga con scripts/descargar-modelo-voz.ps1.
 */
class VoiceRecognizer(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RecognitionListener {

    /** Pantalla abierta (si la hay): solo se necesita para pedir permisos. */
    var activity: Activity? = null

    companion object {
        const val PERMISSION_REQUEST = 4201
        private const val ASSET_MODEL = "model-es"
        /** Modelo de hablante (opcional) para «Solo mi voz». */
        private const val ASSET_SPK = "model-spk"
        private const val SAMPLE_RATE = 16000f
        private const val MIN_CONFIDENCE = 0.6

        private val HEADPHONE_TYPES = buildSet {
            add(AudioDeviceInfo.TYPE_WIRED_HEADSET)
            add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES)
            add(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
            add(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) add(AudioDeviceInfo.TYPE_USB_HEADSET)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val methodChannel = MethodChannel(messenger, "smartbuds/voice")
    private val eventChannel = EventChannel(messenger, "smartbuds/voice/events")
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null

    private var model: Model? = null
    private var spkModel: SpeakerModel? = null
    /** Frases permitidas (JSON) para Vosk; null = escucha libre. */
    private var grammarJson: String? = null
    /** false = escucha abierta (sin música sonando, para «pon …»). */
    private var grammarEnabled = true
    private var speechService: SpeechService? = null

    /** El usuario quiere que SmartBuds escuche (aunque esté en pausa un momento). */
    private var wanted = false

    /** Pausa pedida desde Dart (p. ej. audífonos desconectados). */
    private var pausedByUser = false

    /** Cada frase reconocida es una sesión; Dart la usa para no repetir comandos. */
    private var session = 0

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var oneShotService: SpeechService? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = emitHeadphones()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = emitHeadphones()
    }

    init {
        LibVosk.setLogLevel(LogLevel.WARNINGS)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        audioManager.registerAudioDeviceCallback(deviceCallback, main)
        initTts()
    }

    fun dispose() {
        wanted = false
        stopVosk()
        VoiceForegroundService.stop(context)
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        oneShotService?.shutdown()
        tts?.shutdown()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        worker.execute {
            model?.close(); model = null
            spkModel?.close(); spkModel = null
        }
        worker.shutdown()
    }

    // ---------------------------------------------------------------- Métodos

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(modelBundled())
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermissions(result)
            "start" -> {
                if (!hasPermission()) {
                    result.error("PERMISSION", "Falta el permiso de micrófono", null)
                    return
                }
                val phrases = call.argument<List<String>>("grammar")
                grammarJson = if (phrases.isNullOrEmpty()) null
                else org.json.JSONArray(phrases).toString()
                grammarEnabled = call.argument<Boolean>("grammarEnabled") != false
                wanted = true
                pausedByUser = false
                VoiceForegroundService.start(context)
                startVosk()
                result.success(true)
            }
            "stop" -> {
                wanted = false
                stopVosk()
                VoiceForegroundService.stop(context)
                emit("state", mapOf("listening" to false))
                result.success(true)
            }
            "setPaused" -> {
                pausedByUser = call.argument<Boolean>("paused") == true
                if (pausedByUser) stopVosk() else if (wanted) startVosk()
                emit("state", mapOf("listening" to (wanted && !pausedByUser), "paused" to pausedByUser))
                result.success(true)
            }
            "speak" -> {
                speak(
                    call.argument<String>("text") ?: "",
                    (call.argument<Number>("rate") ?: 1.0).toFloat(),
                    (call.argument<Number>("pitch") ?: 1.0).toFloat(),
                )
                result.success(true)
            }
            "listenOnce" -> listenOnce(result)
            "setGrammarEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") != false
                if (enabled != grammarEnabled) {
                    grammarEnabled = enabled
                    reloadRecognizer()
                }
                result.success(true)
            }
            "setGrammar" -> {
                val phrases = call.argument<List<String>>("grammar")
                grammarJson = if (phrases.isNullOrEmpty()) null
                else org.json.JSONArray(phrases).toString()
                reloadRecognizer()
                result.success(true)
            }
            "headphonesConnected" -> result.success(headphonesConnected())
            "speakerAvailable" -> result.success(assetBundled(ASSET_SPK))
            else -> result.notImplemented()
        }
    }

    /** Micrófono y, en Android 13+, notificaciones (para el aviso de escucha). */
    private fun requestPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        val needed = mutableListOf<String>()
        if (!hasPermission()) needed += Manifest.permission.RECORD_AUDIO
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) needed += Manifest.permission.POST_NOTIFICATIONS
        if (needed.isEmpty()) {
            result.success(true)
            return
        }
        val screen = activity
        if (screen == null) {
            result.success(hasPermission()) // sin pantalla no se pueden pedir permisos
            return
        }
        pendingPermission = result
        screen.requestPermissions(needed.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.success(hasPermission())
        pendingPermission = null
        return true
    }

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun modelBundled(): Boolean = assetBundled(ASSET_MODEL)

    private fun assetBundled(name: String): Boolean = try {
        !context.assets.list(name).isNullOrEmpty()
    } catch (_: Exception) {
        false
    }

    // ------------------------------------------------------------- Vosk

    private fun startVosk() {
        if (speechService != null || !wanted || pausedByUser) return
        emit("state", mapOf("listening" to false, "loading" to true))
        worker.execute {
            try {
                val m = model ?: Model(prepareAsset(ASSET_MODEL).absolutePath).also { model = it }
                if (spkModel == null && assetBundled(ASSET_SPK)) {
                    spkModel = try {
                        SpeakerModel(prepareAsset(ASSET_SPK).absolutePath)
                    } catch (_: Exception) {
                        null
                    }
                }
                val recognizer = buildRecognizer(m)
                main.post {
                    if (!wanted || pausedByUser || speechService != null) {
                        recognizer.close()
                        return@post
                    }
                    try {
                        val service = SpeechService(recognizer, SAMPLE_RATE)
                        service.startListening(this)
                        speechService = service
                        emit("state", mapOf("listening" to true))
                    } catch (e: Exception) {
                        emitError("No se pudo abrir el micrófono: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                emitError("No se pudo cargar el modelo de voz: ${e.message}")
            }
        }
    }

    /**
     * Con lista de frases (gramática) Vosk solo elige entre las órdenes, y
     * entiende mucho mejor con música de fondo. Con modelo de hablante, cada
     * frase trae además una «huella» de la voz para «Solo mi voz».
     */
    /** Vuelve a crear el reconocedor con la configuración nueva (si está escuchando). */
    private fun reloadRecognizer() {
        if (speechService == null) return
        stopVosk()
        startVosk()
    }

    private fun buildRecognizer(m: Model): Recognizer {
        val grammar = if (grammarEnabled) grammarJson else null
        val recognizer = if (grammar != null) {
            try {
                Recognizer(m, SAMPLE_RATE, grammar)
            } catch (_: Exception) {
                Recognizer(m, SAMPLE_RATE)
            }
        } else Recognizer(m, SAMPLE_RATE)
        recognizer.setWords(true)
        spkModel?.let { spk ->
            try {
                recognizer.setSpeakerModel(spk)
            } catch (_: Exception) {
            }
        }
        return recognizer
    }

    private fun stopVosk() {
        speechService?.stop()
        speechService?.shutdown()
        speechService = null
    }

    /** Copia un modelo de assets a la memoria interna una sola vez. */
    private fun prepareAsset(name: String): File {
        val target = File(context.filesDir, name)
        val marker = File(target, ".ready")
        if (marker.exists()) return target
        target.deleteRecursively()
        copyAssetDir(name, target)
        marker.writeText("ok")
        return target
    }

    private fun copyAssetDir(assetPath: String, dest: File) {
        val children = context.assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            dest.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                dest.outputStream().use { input.copyTo(it) }
            }
            return
        }
        dest.mkdirs()
        for (child in children) copyAssetDir("$assetPath/$child", File(dest, child))
    }

    override fun onPartialResult(hypothesis: String?) {}

    override fun onResult(hypothesis: String?) {
        val json = try {
            JSONObject(hypothesis ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val raw = json.optString("text", "").trim()
        if (raw.isNotEmpty() && !raw.contains("[unk]") && confident(json)) {
            val spkArray = json.optJSONArray("spk")
            val spk = if (spkArray == null) null
            else List(spkArray.length()) { spkArray.optDouble(it) }
            emit("final", mapOf("texts" to listOf(raw), "spk" to spk))
        }
        session++
    }

    /** Descarta frases que Vosk no está seguro de haber oído (ruido, canto). */
    private fun confident(json: JSONObject): Boolean {
        val words = json.optJSONArray("result") ?: return true
        for (i in 0 until words.length()) {
            val conf = words.optJSONObject(i)?.optDouble("conf", 1.0) ?: 1.0
            if (conf < MIN_CONFIDENCE) return false
        }
        return true
    }

    override fun onFinalResult(hypothesis: String?) {
        onResult(hypothesis)
    }

    override fun onError(exception: Exception?) {
        emitError("Error del micrófono: ${exception?.message}")
        stopVosk()
        emit("state", mapOf("listening" to false))
        // Reintenta solo: el micrófono puede estar ocupado un momento.
        main.postDelayed({ if (wanted && !pausedByUser) startVosk() }, 1500)
    }

    override fun onTimeout() {
        stopVosk()
        emit("state", mapOf("listening" to false))
    }

    // ------------------------------------------------------- Respuesta hablada

    private fun initTts() {
        tts = TextToSpeech(context.applicationContext) { status ->
            val t = tts
            if (status == TextToSpeech.SUCCESS && t != null) configureTts(t)
        }
    }

    private fun configureTts(t: TextToSpeech) {
        run {
            val co = t.setLanguage(Locale("es", "CO"))
            if (co == TextToSpeech.LANG_MISSING_DATA || co == TextToSpeech.LANG_NOT_SUPPORTED) {
                t.setLanguage(Locale("es"))
            }
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    main.post {
                        speechService?.setPause(true)
                        emit("speaking", mapOf("on" to true))
                    }
                }

                override fun onDone(utteranceId: String?) {
                    // Pequeña espera para que el eco de la voz no se tome como orden.
                    main.postDelayed({
                        speechService?.setPause(false)
                        emit("speaking", mapOf("on" to false))
                    }, 300)
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    main.post {
                        speechService?.setPause(false)
                        emit("speaking", mapOf("on" to false))
                    }
                }
            })
            ttsReady = true
        }
    }

    private fun speak(text: String, rate: Float = 1f, pitch: Float = 1f) {
        if (!ttsReady || text.isBlank()) return
        // Voz personalizada: velocidad y tono elegidos en Asistente.
        tts?.setSpeechRate(rate.coerceIn(0.5f, 2f))
        tts?.setPitch(pitch.coerceIn(0.5f, 2f))
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), "smartbuds-${System.nanoTime()}")
    }

    /** Botón «Detener» de la notificación. */
    fun stopFromNotification() {
        main.post {
            wanted = false
            stopVosk()
            VoiceForegroundService.stop(context)
            emit("state", mapOf("listening" to false, "stopped" to true))
        }
    }

    // ----------------------------------------------- Escucha precisa (una frase)

    /**
     * Escucha una sola frase con el reconocedor del sistema (Google), que entiende
     * mejor nombres de canciones. Vosk se detiene mientras tanto (el micrófono
     * no puede compartirse) y vuelve a escuchar al terminar.
     */
    /**
     * Escucha UNA frase libre (nombre de canción o artista) con Vosk sin
     * gramática, y luego vuelve al modo de órdenes. Funciona sin internet y no
     * pausa la música (el reconocedor de Google sí la pausaba).
     */
    private fun listenOnce(result: MethodChannel.Result) {
        val m = model
        if (m == null) {
            result.success(null)
            return
        }
        stopVosk()
        var answered = false
        fun finish(text: String?) {
            if (answered) return
            answered = true
            main.post {
                oneShotService?.stop()
                oneShotService?.shutdown()
                oneShotService = null
                startVosk()
                result.success(text)
            }
        }
        // Margen para que termine de sonar «¿Qué canción?» antes de escuchar.
        main.postDelayed({
            if (answered) return@postDelayed
            try {
                val service = SpeechService(Recognizer(m, SAMPLE_RATE), SAMPLE_RATE)
                oneShotService = service
                service.startListening(object : RecognitionListener {
                    override fun onPartialResult(hypothesis: String?) {}
                    override fun onResult(hypothesis: String?) = take(hypothesis)
                    override fun onFinalResult(hypothesis: String?) = take(hypothesis)
                    override fun onError(exception: Exception?) = finish(null)
                    override fun onTimeout() = finish(null)

                    private fun take(hypothesis: String?) {
                        val text = try {
                            JSONObject(hypothesis ?: "{}").optString("text", "").trim()
                        } catch (_: Exception) {
                            ""
                        }
                        if (text.isNotEmpty()) finish(text)
                    }
                })
            } catch (_: Exception) {
                finish(null)
            }
        }, 1500)
        // Seguridad: no quedarse esperando para siempre.
        main.postDelayed({ finish(null) }, 12_000)
    }

    // ------------------------------------------------------------- Audífonos

    private fun headphonesConnected(): Boolean =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in HEADPHONE_TYPES }

    private fun emitHeadphones() {
        emit("headphones", mapOf("connected" to headphonesConnected()))
    }

    // ----------------------------------------------------------------- Eventos

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        emitHeadphones()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emitError(message: String) = emit("error", mapOf("message" to message))

    private fun emit(type: String, data: Map<String, Any?>) {
        val payload = HashMap<String, Any?>(data)
        payload["type"] = type
        payload["session"] = session
        main.post { sink?.success(payload) }
    }
}
