plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.goodloop.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "pl.goodloop.app"
        vectorDrawables.useSupportLibrary = true
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: prawdziwy keystore. Na razie podpis kluczem debug —
            // instalowalny przez "nieznane źródła", wystarcza do testów.
            signingConfig = signingConfigs.getByName("debug")

            // Wyłączony R8 na czas buildów testowych — flutter_local_notifications
            // 17.x wysypuje się z włączonym shrinkerem ("TypeToken must be created
            // with a type argument") przy odczycie zaplanowanych powiadomień.
            // Do prawdziwego release: isMinifyEnabled = true + poniższe proguardFiles
            // (reguły są w proguard-rules.pro) i przetestować powiadomienia.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Kotlin syntax uses parentheses and double quotes
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}