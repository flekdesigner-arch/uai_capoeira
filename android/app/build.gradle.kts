plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.uai_capoeira.uai_capoeira"
    compileSdk = 36
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
        applicationId = "com.uai_capoeira.uai_capoeira"
        minSdk = flutter.minSdkVersion  // ✅ FIXO EM 23 (NÃO USE flutter.minSdkVersion)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-messaging")  // ✅ ADICIONADO
    implementation("com.google.firebase:firebase-firestore")  // ✅ ADICIONADO
    implementation("com.google.firebase:firebase-storage")    // ✅ ADICIONADO

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    implementation("androidx.multidex:multidex:2.0.1")

    // ✅ DEPENDÊNCIAS PARA PERMISSÕES DE ARMAZENAMENTO
    implementation("androidx.core:core:1.12.0")
    implementation("androidx.activity:activity:1.8.0")
}
