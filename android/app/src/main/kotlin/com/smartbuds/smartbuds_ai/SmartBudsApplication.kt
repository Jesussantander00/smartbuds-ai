package com.smartbuds.smartbuds_ai

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * El motor de SmartBuds (Flutter + módulos nativos) vive en la aplicación, no en
 * la pantalla. Así, mientras el servicio de escucha esté activo, SmartBuds sigue
 * entendiendo tus órdenes aunque cierres la app desde recientes.
 */
class SmartBudsApplication : Application() {

    companion object {
        const val ENGINE_ID = "smartbuds_engine"
        var instance: SmartBudsApplication? = null
            private set
    }

    lateinit var engine: FlutterEngine
        private set
    var mediaConnector: MediaSessionConnector? = null
        private set
    var voiceRecognizer: VoiceRecognizer? = null
        private set
    var inAppPlayer: InAppPlayer? = null
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        engine = FlutterEngine(this)
        // Primero los módulos nativos, para que estén listos cuando Dart arranque.
        val messenger = engine.dartExecutor.binaryMessenger
        mediaConnector = MediaSessionConnector(this, messenger)
        voiceRecognizer = VoiceRecognizer(this, messenger)
        inAppPlayer = InAppPlayer(this, messenger)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }
}
