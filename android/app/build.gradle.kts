plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadStoreFile = System.getenv("FIXEASE_UPLOAD_STORE_FILE")
val uploadStorePassword = System.getenv("FIXEASE_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = System.getenv("FIXEASE_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = System.getenv("FIXEASE_UPLOAD_KEY_PASSWORD")
val hasUploadSigning = listOf(
    uploadStoreFile,
    uploadStorePassword,
    uploadKeyAlias,
    uploadKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.oraik.fixease"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.oraik.fixease"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasUploadSigning) {
        signingConfigs.create("release") {
            storeFile = file(uploadStoreFile!!)
            storePassword = uploadStorePassword!!
            keyAlias = uploadKeyAlias!!
            keyPassword = uploadKeyPassword!!
        }
    }

    buildTypes {
        release {
            // Use the existing Play upload key from the local environment. A
            // release is intentionally left unsigned when credentials are absent.
            if (hasUploadSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
