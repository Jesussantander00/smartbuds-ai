package com.smartbuds.smartbuds_ai

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lleva a Flutter las acciones de los accesos rápidos del ícono y del widget
 * («Pon algo que me guste», «Algo nuevo», «Cambiar», «Escuchar»).
 * Si Flutter aún está arrancando, la acción espera hasta que avise «listo».
 */
class ActionBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        const val EXTRA_ACTION = "smartbuds_action"
        val KNOWN = setOf("listen", "next", "favorite", "discover")
    }

    private val channel = MethodChannel(messenger, "smartbuds/actions")
    private val main = Handler(Looper.getMainLooper())
    private var ready = false
    private val pending = mutableListOf<String>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispatch(action: String?) {
        if (action == null || action !in KNOWN) return
        main.post {
            if (ready) channel.invokeMethod("action", action) else pending += action
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                ready = true
                val queued = pending.toList()
                pending.clear()
                queued.forEach { channel.invokeMethod("action", it) }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}
