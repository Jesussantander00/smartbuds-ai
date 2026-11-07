package com.smartbuds.smartbuds_ai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var mediaConnector: MediaSessionConnector? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaConnector = MediaSessionConnector(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaConnector?.dispose()
        mediaConnector = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
