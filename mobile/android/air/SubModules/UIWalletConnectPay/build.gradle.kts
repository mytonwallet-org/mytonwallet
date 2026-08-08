plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uiwalletconnectpay"
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
