plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.        
        minSdk = 35 // Requisito del SDK de Chafon (APK de prueba cf_tech_release_v1.0.2_20251217103040.apk requiere Android 15+)
        targetSdk = 35 // Forzado a 35 para alinearse con minSdk y evitar la descarga de múltiples SDKs en Docker
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

			// Obfuscation (also known as minification)
			isMinifyEnabled = false // 'false' si quieres apagar el ofuscador por completo
            // Shrinking
			isShrinkResources = false

            // Cargamos el optimizador oficial de Google + tu archivo personalizado
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
            )			
        }
    }
}

flutter {
    source = "../.."
}
