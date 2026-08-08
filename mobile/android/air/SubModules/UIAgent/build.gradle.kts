plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uiagent"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.blurview)
    implementation(project("$airSubModulePath:UIInAppBrowser"))
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletCore"))
    implementation(project("$airSubModulePath:Icons"))
}
