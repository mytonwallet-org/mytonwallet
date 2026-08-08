plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uiassets"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.fresco)
    implementation(libs.charts)
    implementation(libs.lottie)
    implementation(project("$airSubModulePath:UIAgent"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:UITransaction"))
    implementation(project("$airSubModulePath:UISend"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:UIStake"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:UIReceive"))
    implementation(project("$airSubModulePath:Ledger"))
    implementation(project("$airSubModulePath:vkryl:android"))
}
