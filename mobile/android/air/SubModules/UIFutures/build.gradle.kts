plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uifutures"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.fresco)
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:UIMarket"))
    implementation(project("$airSubModulePath:UIAssets"))
    implementation(project("$airSubModulePath:UISwap"))
    implementation(project("$airSubModulePath:UIPasscode"))
    implementation(project("$airSubModulePath:UISettings"))
    implementation(project("$airSubModulePath:Blur3"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:vkryl:android"))
}
