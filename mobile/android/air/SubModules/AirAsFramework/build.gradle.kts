plugins {
    id("com.android.library")
    alias(libs.plugins.jetbrains.kotlin.android)
}

android {
    namespace = "org.mytonwallet.app_air.airasframework"
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
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.biometric)
    implementation(libs.fresco)
    implementation(libs.zxing)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:UICreateWallet"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:UIHome"))
    implementation(project("$airSubModulePath:UISend"))
    implementation(project("$airSubModulePath:UIReceive"))
    implementation(project("$airSubModulePath:UIStake"))
    implementation(project("$airSubModulePath:UIAssets"))
    implementation(project("$airSubModulePath:UIBrowser"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:UITonConnect"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:UITransaction"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:Ledger"))
    implementation(project("$airSubModulePath:QRScan"))
    implementation(project("$airSubModulePath:UIWidgetsConfigurations"))
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
