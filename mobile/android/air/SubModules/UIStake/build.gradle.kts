plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uistake"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.material)
    implementation(libs.lottie)
    implementation(libs.fresco)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:vkryl:android"))
    implementation(project("$airSubModulePath:Ledger"))
}
