import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Identifiant de l'application — LA seule source (Android ; iOS : PRODUCT_BUNDLE_IDENTIFIER).
// PROVISOIRE : à fixer AVANT la première publication sur les stores (il ne peut plus changer
// ensuite), idéalement sur un nom de domaine possédé, écrit à l'envers. Décision de l'utilisateur
// du 2026-09-28 : « décider plus tard ». Les variantes dev/staging en dérivent par suffixe.
val thyApplicationId = "com.thyecosystem.app"

// Signature release : clé fournie par android/key.properties (jamais versionné, voir .gitignore).
// Sans ce fichier, la release est signée avec la clé de debug — suffisant pour vérifier un build en
// CI, JAMAIS pour publier (un store refuse de toute façon la clé de debug).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = thyApplicationId
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = thyApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // `resValue` (nom de l'app par variante, ci-dessous) : désactivé par défaut depuis l'Android
    // Gradle Plugin 9 — sans cette ligne, toute variante qui en déclare un fait échouer le build.
    buildFeatures {
        resValues = true
    }

    // Trois environnements installables côte à côte sur un même téléphone (identifiants distincts).
    // Côté Dart, la variante est lue par `appFlavor` (lib/core/config/app_environment.dart).
    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "THY Dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "THY Staging")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "THY")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }
}

if (!hasReleaseKey) {
    logger.warn("THY : android/key.properties absent — la release est signée avec la clé de DEBUG (non publiable).")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
