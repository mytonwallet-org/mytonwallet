plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uitransaction"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.fresco)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:UISend"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:UIStake"))
    implementation(project("$airSubModulePath:UIPasscode"))
}
