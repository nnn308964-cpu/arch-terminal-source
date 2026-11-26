pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Flutter 3.47's Gradle plugin currently targets AGP 9.1 APIs.
    // Newer AGP 9.3 removes the legacy API that Flutter still accesses.
    id("com.android.application") version "9.5.3" apply false
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}

include(":app")
