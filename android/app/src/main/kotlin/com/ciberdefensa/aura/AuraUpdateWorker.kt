package com.ciberdefensa.aura

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class AuraUpdateWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val notificationManager =
            applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) == null
        ) {
            notificationManager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val notification = NotificationCompat.Builder(
            applicationContext,
            NOTIFICATION_CHANNEL_ID,
        )
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(NOTIFICATION_TEXT)
            .setStyle(NotificationCompat.BigTextStyle().bigText(NOTIFICATION_TEXT))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()

        try {
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (error: SecurityException) {
            Log.w(TAG, "Notification permission is unavailable.", error)
        }

        return Result.success()
    }

    private companion object {
        const val TAG = "AuraUpdateWorker"
        const val NOTIFICATION_CHANNEL_ID = "com.aura.mobile.defens.vpn"
        const val NOTIFICATION_CHANNEL_NAME = "Aura Centinela"
        const val NOTIFICATION_ID = 8817
        const val NOTIFICATION_TITLE =
            "🧠 Aura Mobile Defens · Actualización Recomendada"
        const val NOTIFICATION_TEXT =
            "Han pasado 7 días desde tu último blindaje. Escribe o di " +
                "'actualizar sistema de defensas' para renovar la matriz de la IA."
    }
}
