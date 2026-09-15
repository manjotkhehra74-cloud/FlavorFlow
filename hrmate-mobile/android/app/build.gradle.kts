import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "in.flavorflow.hrmate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Phases 0–4 ship as "HRMate Beta" (suffix .beta below) so the native
        // app installs NEXT TO the live WebView shell. Phase 5 removes the
        // suffix and signs with the v1.0.4 keystore (ARCHITECTURE.md §6).
        applicationId = "in.flavorflow.hrmate"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "HRMate")
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                (keystoreProperties["storeType"] as String?)?.let { storeType = it }
            }
        }
    }

    buildTypes {
        release {
            val cfg = signingConfigs.findByName("release")
            signingConfig = if (cfg?.storeFile != null) cfg else signingConfigs.getByName("debug")
        }
    }

    flavorDimensions += "track"
    productFlavors {
        create("beta") {
            dimension = "track"
            applicationIdSuffix = ".beta"
            versionNameSuffix = "-beta"
            resValue("string", "app_name", "HRMate Beta")
        }
        create("prod") {
            dimension = "track"
            resValue("string", "app_name", "HRMate")
        }
    }
}

kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
