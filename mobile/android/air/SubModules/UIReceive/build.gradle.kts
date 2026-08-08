plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uireceive"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.fresco)
    implementation(project("$airSubModulePath:OverScroll"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:vkryl:core"))
    implementation(project("$airSubModulePath:vkryl:android"))
}
