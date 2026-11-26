package com.example.arch_terminal

import android.app.Application
import android.content.Context

class ArchTerminalApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        StartupDiagnostics.initialize(this)
        StartupCrashHandler.install()
        StartupDiagnostics.begin("STARTUP_01_APPLICATION_ATTACH")
        StartupDiagnostics.ok("STARTUP_01_APPLICATION_ATTACH")
    }

    override fun onCreate() {
        StartupDiagnostics.begin("STARTUP_02_APPLICATION_CREATE")
        try {
            super.onCreate()
            StartupDiagnostics.ok("STARTUP_02_APPLICATION_CREATE")
        } catch (error: Throwable) {
            StartupDiagnostics.failed("STARTUP_02_APPLICATION_CREATE", error)
            throw error
        }
    }
}
