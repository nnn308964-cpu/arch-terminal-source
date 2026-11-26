plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val minimumAndroidSdk = 24

android {
    namespace = "com.example.arch_terminal"
    // The current Android plugins compile against API 37; this does not change
    // the app's API 24 installation minimum.
    compileSdk = 37
    // Native plugins in this release require NDK 28.2.13676358.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.arch_terminal"
        // API 24 matches the current Flutter Android toolchain guidance.
        // Android 6.0 (API 23) is no longer installable from this build.
        minSdk = minimumAndroidSdk
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // A single APK embeds only the small PRoot binaries for both supported
        // ARM ABIs. RootFS archives are downloaded and verified on first use.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        getByName("debug") {
            // ARM32 devices can run Android versions that require the legacy
            // JAR signature. Keep V2 as well for modern Android versions.
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            // TODO: replace the debug signing key with a protected release key before publishing.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
