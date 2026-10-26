import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use(releaseKeyProperties::load)
}

android {
    namespace = "se.falt.falt"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "se.falt.falt"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeyProperties.getProperty("keyAlias")
            keyPassword = releaseKeyProperties.getProperty("keyPassword")
            storeFile = releaseKeyProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = releaseKeyProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (releaseKeyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (gradle.startParameter.taskNames.any {
                it.contains("Release", ignoreCase = true)
            }) {
                throw GradleException(
                    "Missing android/key.properties; release builds must use a user-owned keystore."
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
