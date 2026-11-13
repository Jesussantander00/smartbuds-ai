package com.smartbuds.smartbuds_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Servicio en primer plano de tipo micrófono: mantiene a SmartBuds escuchando
 * con la pantalla apagada o la app en segundo plano, con una notificación fija
 * («SmartBuds está escuchando»). Android exige iniciarlo con la app abierta.
 */
class VoiceForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "smartbuds_listening"
        private const val NOTIFICATION_ID = 4202
        private const val ACTION_STOP = "com.smartbuds.smartbuds_ai.STOP_LISTENING"
        private const val ACTION_PREV = "com.smartbuds.smartbuds_ai.MEDIA_PREV"
        private const val ACTION_TOGGLE = "com.smartbuds.smartbuds_ai.MEDIA_TOGGLE"
        private const val ACTION_NEXT = "com.smartbuds.smartbuds_ai.MEDIA_NEXT"
        private const val ACTION_LIKE = "com.smartbuds.smartbuds_ai.LIKE"

        fun start(context: Context) {
            val intent = Intent(context, VoiceForegroundService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // Sin permiso para iniciarlo ahora (p. ej. app en segundo plano):
                // la escucha sigue funcionando mientras la app esté abierta.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val media = when (intent?.action) {
            ACTION_PREV -> "previous"
            ACTION_TOGGLE -> "togglePlayPause"
            ACTION_NEXT -> "next"
            else -> null
        }
        if (intent?.action == ACTION_LIKE) {
            // «Me gusta» desde la notificación (o el reloj que la refleje).
            SmartBudsApplication.instance?.actions?.dispatch("like")
            return START_STICKY
        }
        if (media != null) {
            MediaSessionConnector.instance?.commandActive(media)
            return START_STICKY
        }
        if (intent?.action == ACTION_STOP) {
            SmartBudsApplication.instance?.voiceRecognizer?.stopFromNotification()
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        val notification = buildNotification()
        try {
            // El tipo «micrófono» existe desde Android 11 (API 30).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Escucha de SmartBuds", NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Aviso mientras SmartBuds escucha tus comandos de voz" }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, VoiceForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        fun mediaAction(code: Int, action: String, icon: Int, label: String) =
            Notification.Action.Builder(
                android.graphics.drawable.Icon.createWithResource(this, icon),
                label,
                PendingIntent.getService(
                    this, code,
                    Intent(this, VoiceForegroundService::class.java).setAction(action),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            ).build()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("SmartBuds está escuchando")
            .setContentText("Di «Cambia», «Pausa» o «Busca» y una canción")
            .setContentIntent(open)
            .setOngoing(true)
            .setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
            .addAction(mediaAction(10, ACTION_PREV, android.R.drawable.ic_media_previous, "Anterior"))
            .addAction(mediaAction(11, ACTION_TOGGLE, android.R.drawable.ic_media_pause, "Pausa"))
            .addAction(mediaAction(12, ACTION_NEXT, android.R.drawable.ic_media_next, "Siguiente"))
            .addAction(mediaAction(13, ACTION_LIKE, android.R.drawable.btn_star_big_on, "Me gusta"))
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(
                        this, android.R.drawable.ic_menu_close_clear_cancel
                    ),
                    "Detener", stop
                ).build()
            )
            .build()
    }
}
