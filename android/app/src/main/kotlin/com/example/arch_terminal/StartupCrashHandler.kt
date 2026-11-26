package com.example.arch_terminal

/** Records uncaught Java/Kotlin failures, then preserves Android's normal crash handling. */
internal class StartupCrashHandler(
    private val previous: Thread.UncaughtExceptionHandler?,
) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(thread: Thread, error: Throwable) {
        try {
            StartupDiagnostics.failed("STARTUP_UNCAUGHT", error)
        } catch (_: Throwable) {
            // Never allow diagnostics to conceal the original fatal error.
        }
        previous?.uncaughtException(thread, error)
    }

    companion object {
        fun install() {
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            if (previous is StartupCrashHandler) return
            Thread.setDefaultUncaughtExceptionHandler(StartupCrashHandler(previous))
        }
    }
}
