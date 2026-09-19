import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Phase 6 (push): applied only when android/app/google-services.json exists, so a
    // checkout without the Firebase config still builds (push simply stays off in it).
    id("com.google.gms.google-services") apply false
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("HRMate: android/app/google-services.json missing — building WITHOUT push notifications")
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
        // beta flavor = in.flavorflow.hrmate.beta (test installs next to the
        // prod build); prod flavor = in.flavorflow.hrmate, signed via
        // key.properties when the hrmate_release env group is set (ARCHITECTURE.md §9).
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
