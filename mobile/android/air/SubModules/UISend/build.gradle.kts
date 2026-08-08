plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uisend"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.lottie)
    implementation(libs.fresco)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:QRScan"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
    implementation(project("$airSubModulePath:Ledger"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
}
