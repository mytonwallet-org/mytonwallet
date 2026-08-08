plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.uiportfolio"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.blurview)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(project("$airSubModulePath:UIComponents"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletCore"))
}
