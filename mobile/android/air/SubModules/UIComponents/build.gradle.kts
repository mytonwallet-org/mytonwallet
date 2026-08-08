plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uicomponents"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.material)
    implementation(libs.lottie)
    implementation(libs.fresco)
    implementation(libs.fresco.middleware)
    implementation(libs.fresco.ui.common)
    implementation(libs.androidsvg)
    implementation(libs.zxing)
    implementation(libs.charts)
    implementation(libs.blurview)
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletNative"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
    implementation(libs.androidx.palette.ktx)
}
