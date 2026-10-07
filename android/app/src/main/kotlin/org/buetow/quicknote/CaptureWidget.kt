package org.buetow.quicknote

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: a "Quick note" bar. Tapping the text opens the capture
 * dialog ([CaptureActivity]) over the home screen; tapping the icon opens
 * the app.
 */
class CaptureWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val capture = PendingIntent.getActivity(
            context, 0,
            Intent(context, CaptureActivity::class.java)
                .setAction(ACTION_CAPTURE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            flags,
        )
        val open = PendingIntent.getActivity(
            context, 1,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            flags,
        )
        val note = try {
            DefaultNote(context).path
        } catch (e: IllegalArgumentException) {
            "Quicknote.md"
        }
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.capture_widget)
            views.setTextViewText(R.id.widget_text, context.getString(R.string.widget_hint, note))
            views.setOnClickPendingIntent(R.id.widget_text, capture)
            views.setOnClickPendingIntent(R.id.widget_icon, open)
            manager.updateAppWidget(id, views)
        }
    }

    companion object {
        const val ACTION_CAPTURE = "org.buetow.quicknote.CAPTURE"
    }
}
