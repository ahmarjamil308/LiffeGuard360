package com.lifeguard360.lifeguard360.monitoring

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.lifeguard360.lifeguard360.MainActivity

/**
 * Android BroadcastReceiver for device reboot events.
 *
 * NOTE ON ANDROID 14+ COMPLIANCE:
 * Android 14 strictly prohibits apps from launching foreground services directly
 * from BOOT_COMPLETED receivers without prior user interaction.
 * Therefore, this receiver posts a prompt notification allowing the user to resume monitoring with 1 tap.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        const val REBOOT_CHANNEL_ID = "lifeguard360_reboot_channel"
        const val REBOOT_NOTIFICATION_ID = 1002
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            postRebootResumeNotification(context)
        }
    }

    private fun postRebootResumeNotification(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                REBOOT_CHANNEL_ID,
                "LifeGuard 360 Reboot Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminds user to reactivate monitoring after phone restart"
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("resume_monitoring_after_reboot", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, REBOOT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("LifeGuard 360: Device Rebooted")
            .setContentText("Tap to re-activate intelligent safety monitoring and emergency GPS protection.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(REBOOT_NOTIFICATION_ID, notification)
    }
}
