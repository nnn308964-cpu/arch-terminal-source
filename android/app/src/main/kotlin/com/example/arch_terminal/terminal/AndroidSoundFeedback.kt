package com.example.arch_terminal.terminal

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import kotlin.math.roundToInt

object SoundFeedbackPolicy {
    const val EVENT_TAP = "tap"
    const val EVENT_SUCCESS = "success"
    const val EVENT_ERROR = "error"
    const val EVENT_TERMINAL = "terminal"

    fun toneFor(event: String): Int = when (event) {
        EVENT_SUCCESS -> ToneGenerator.TONE_PROP_ACK
        EVENT_ERROR -> ToneGenerator.TONE_PROP_NACK
        EVENT_TERMINAL -> ToneGenerator.TONE_PROP_BEEP2
        else -> ToneGenerator.TONE_PROP_BEEP
    }

    fun levelFor(volume: Float): Int = (volume.coerceIn(0f, 1f) * 100).roundToInt()
}

object AndroidSoundFeedback {
    private const val PREFERENCES = "terminal_ui"

    fun play(context: Context, event: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean("soundEnabled", true)) return
        val level = SoundFeedbackPolicy.levelFor(
            preferences.getFloat("soundVolume", 0.35f),
        )
        if (level == 0) return
        val tone = ToneGenerator(AudioManager.STREAM_MUSIC, level)
        tone.startTone(SoundFeedbackPolicy.toneFor(event), 90)
        Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 160)
    }
}
