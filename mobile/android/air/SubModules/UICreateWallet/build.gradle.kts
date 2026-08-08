plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uicreatewallet"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.lottie)
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:UIHome"))
    implementation(project("$airSubModulePath:Ledger"))
    implementation(project("$airSubModulePath:Icons"))
}
