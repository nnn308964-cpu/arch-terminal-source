package com.example.arch_terminal.terminal

import android.content.Context

private const val TERMINAL_UI_PREFERENCES = "terminal_ui"
private const val LANGUAGE_KEY = "language"

fun Context.runtimeText(arabic: String, english: String): String =
    if (getSharedPreferences(TERMINAL_UI_PREFERENCES, Context.MODE_PRIVATE).getString(LANGUAGE_KEY, "ar") == "en") english else arabic
