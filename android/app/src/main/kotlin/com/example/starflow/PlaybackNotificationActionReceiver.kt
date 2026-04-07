package com.example.starflow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PlaybackNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != PlaybackSystemSessionManager.ACTION_REMOTE_COMMAND) {
            return
        }
        val command = intent.getStringExtra(PlaybackSystemSessionManager.EXTRA_COMMAND)
            ?.trim()
            .orEmpty()
        if (command.isEmpty()) {
            return
        }
        val positionMs = if (intent.hasExtra(PlaybackSystemSessionManager.EXTRA_POSITION_MS)) {
            intent.getLongExtra(PlaybackSystemSessionManager.EXTRA_POSITION_MS, 0L)
        } else {
            null
        }
        PlaybackSystemSessionManager.dispatchNotificationCommand(command, positionMs)
    }
}
