package com.smartbuds.smartbuds_ai

import android.content.Context
import android.content.Intent
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
        handleAction(intent)
    }

    /** Accesos rápidos del ícono o botón del widget con la app ya abierta. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAction(intent)
    }

    private fun handleAction(intent: Intent?) {
        val action = intent?.getStringExtra(ActionBridge.EXTRA_ACTION) ?: return
        intent.removeExtra(ActionBridge.EXTRA_ACTION) // que no se repita al girar
        SmartBudsApplication.instance?.actions?.dispatch(action)
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
