package com.smartbuds.smartbuds_ai

import android.service.notification.NotificationListenerService

/**
 * Servicio autorizado por el usuario en Ajustes → Acceso a notificaciones.
 * No lee el contenido de las notificaciones: su única función es que
 * MediaSessionManager.getActiveSessions() acepte nuestra app.
 */
class SmartBudsNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        MediaSessionConnector.instance?.onListenerConnected()
    }
}
