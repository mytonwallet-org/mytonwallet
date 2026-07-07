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
    namespace = "org.mytonwallet.app_air.uiwalletconnectpay"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

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
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.material)
    implementation(libs.fresco)
    implementation(libs.lottie)
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:UITransaction"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
    implementation(project("$airSubModulePath:Ledger"))
}
