package com.smartbuds.smartbuds_ai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Widget de la pantalla de inicio: Escuchar · Cambiar · Algo que me guste.
 * «Escuchar» abre la app (Android exige que el micrófono se active con la app
 * visible); los otros dos funcionan sin abrirla.
 */
class SmartBudsWidget : AppWidgetProvider() {

    companion object {
        private const val ACTION = "com.smartbuds.smartbuds_ai.WIDGET_ACTION"
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.smartbuds_widget)
            views.setOnClickPendingIntent(R.id.widget_listen, openApp(context, "listen", 1))
            views.setOnClickPendingIntent(R.id.widget_next, broadcast(context, "next", 2))
            views.setOnClickPendingIntent(R.id.widget_favorite, broadcast(context, "favorite", 3))
            manager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION) return
        val action = intent.getStringExtra(ActionBridge.EXTRA_ACTION)
        // Al recibir esto, Android ya creó SmartBudsApplication (y su motor).
        SmartBudsApplication.instance?.actions?.dispatch(action)
    }

    private fun broadcast(context: Context, action: String, code: Int): PendingIntent {
        val intent = Intent(context, SmartBudsWidget::class.java)
            .setAction(ACTION)
            .putExtra(ActionBridge.EXTRA_ACTION, action)
        return PendingIntent.getBroadcast(
            context, code, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun openApp(context: Context, action: String, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(ActionBridge.EXTRA_ACTION, action)
        return PendingIntent.getActivity(
            context, code, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
