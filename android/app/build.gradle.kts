import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "in.flavorflow.sauce_erp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.flavorflow.flavorflow_erp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Codemagic injects these when the workflow uses android_signing
            val cmPath = System.getenv("CM_KEYSTORE_PATH")
            if (!cmPath.isNullOrBlank()) {
                storeFile = file(cmPath)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
                // PKCS12 keystores (e.g. flavorflow-upload) are auto-detected,
                // but set the type explicitly when the extension isn't .jks.
                if (!cmPath.endsWith(".jks") && !cmPath.endsWith(".keystore")) {
                    storeType = "pkcs12"
                }
            } else if (keystorePropertiesFile.exists()) {
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
            // Signed with the upload keystore on Codemagic (or key.properties
            // locally); falls back to debug keys only when neither exists.
            val cfg = signingConfigs.findByName("release")
            signingConfig = if (cfg?.storeFile != null) cfg else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
