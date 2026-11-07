package com.smartbuds.smartbuds_ai

import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * La pantalla usa el motor que vive en SmartBudsApplication y no lo destruye al
 * cerrarse: la escucha (y todo lo que entiende SmartBuds) sigue funcionando.
 */
class MainActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(SmartBudsApplication.ENGINE_ID)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SmartBudsApplication.instance?.voiceRecognizer?.activity = this
    }

    override fun onDestroy() {
        val voice = SmartBudsApplication.instance?.voiceRecognizer
        if (voice?.activity === this) voice.activity = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val voice = SmartBudsApplication.instance?.voiceRecognizer
        if (voice?.onPermissionResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
