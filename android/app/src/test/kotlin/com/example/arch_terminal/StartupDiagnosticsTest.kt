package com.example.arch_terminal

import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertTrue
import org.junit.Test

class StartupDiagnosticsTest {
    @Test
    fun preservesThePreviousStartupLogWhenANewSessionBegins() {
        val directory = createTempDirectory("startup-diagnostics").toFile()
        try {
            StartupDiagnostics.initializeIn(directory)
            StartupDiagnostics.begin("STARTUP_03_MAIN_ACTIVITY_CREATE")
            StartupDiagnostics.ok("STARTUP_03_MAIN_ACTIVITY_CREATE")

            StartupDiagnostics.initializeIn(directory)
            val report = StartupDiagnostics.reportIn(directory)

            assertTrue(report.contains("== Current startup log =="))
            assertTrue(report.contains("== Previous startup log =="))
            assertTrue(report.contains("STARTUP_03_MAIN_ACTIVITY_CREATE_OK"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun recordsExceptionEvidenceWithoutThrowingFromTheLogger() {
        val directory = createTempDirectory("startup-diagnostics-error").toFile()
        try {
            StartupDiagnostics.initializeIn(directory)
            StartupDiagnostics.failed("STARTUP_04_FLUTTER_ENGINE", IllegalStateException("test failure"))

            val report = StartupDiagnostics.reportIn(directory)

            assertTrue(report.contains("STARTUP_04_FLUTTER_ENGINE_FAILED"))
            assertTrue(report.contains("java.lang.IllegalStateException"))
            assertTrue(report.contains("test failure"))
        } finally {
            directory.deleteRecursively()
        }
    }
}
