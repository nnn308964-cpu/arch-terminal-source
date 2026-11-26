package com.example.arch_terminal.terminal

import android.media.ToneGenerator
import org.junit.Assert.assertEquals
import org.junit.Test

class SoundFeedbackPolicyTest {
    @Test
    fun `maps feedback events to deterministic platform tones`() {
        assertEquals(ToneGenerator.TONE_PROP_BEEP, SoundFeedbackPolicy.toneFor(SoundFeedbackPolicy.EVENT_TAP))
        assertEquals(ToneGenerator.TONE_PROP_ACK, SoundFeedbackPolicy.toneFor(SoundFeedbackPolicy.EVENT_SUCCESS))
        assertEquals(ToneGenerator.TONE_PROP_NACK, SoundFeedbackPolicy.toneFor(SoundFeedbackPolicy.EVENT_ERROR))
    }

    @Test
    fun `clamps sound volume to Android tone generator range`() {
        assertEquals(0, SoundFeedbackPolicy.levelFor(-1f))
        assertEquals(35, SoundFeedbackPolicy.levelFor(0.35f))
        assertEquals(100, SoundFeedbackPolicy.levelFor(2f))
    }
}
