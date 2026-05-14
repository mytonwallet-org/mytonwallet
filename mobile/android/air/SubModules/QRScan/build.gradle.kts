plugins {
    id("com.android.library")
    alias(libs.plugins.jetbrains.kotlin.android)
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

android {
    namespace = "org.mytonwallet.app_air.qrscan"
    compileSdk = 36

    defaultConfig {
        minSdk = 23

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.camera.core)
    implementation(libs.camera.view)
    implementation(libs.camera.lifecycle)
    // camera-camera2 is supplied at runtime by the app flavor:
    //   - gram: explicit gramImplementation in app/build.gradle (thin-client doesn't pull it)
    //   - mytonwallet: pulled transitively by the bundled :capacitor-mlkit-barcode-scanning
    compileOnly(libs.camera.camera2)
    // MLKit barcode-scanning API is supplied at runtime by the app flavor:
    //   - gram: com.google.android.gms:play-services-mlkit-barcode-scanning (thin-client)
    //   - mytonwallet: com.google.mlkit:barcode-scanning (bundled, via :capacitor-mlkit-barcode-scanning)
    // Both share the same com.google.mlkit.vision.barcode.* API surface, so we only need it
    // on the compile classpath here.
    compileOnly(libs.mlkit.barcode.scanning)
    implementation(libs.play.services.base)
    implementation(libs.zxing)
    implementation(libs.material)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
}
