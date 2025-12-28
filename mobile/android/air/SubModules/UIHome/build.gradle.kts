plugins {
    id("com.android.library")
    alias(libs.plugins.jetbrains.kotlin.android)
}

android {
    namespace = "org.mytonwallet.uihome"
    compileSdk = 35

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
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.zxing)
    implementation(libs.fresco)
    implementation(libs.fresco.ui.common)
    implementation(libs.blurview)
    implementation(project("$airSubModulePath:UISend"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:UIStake"))
    implementation(project("$airSubModulePath:UIAssets"))
    implementation(project("$airSubModulePath:UIBrowser"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:UITransaction"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:UITonConnect"))
    implementation(project("$airSubModulePath:UIWidgetsConfigurations"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:QRScan"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:UIReceive"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
