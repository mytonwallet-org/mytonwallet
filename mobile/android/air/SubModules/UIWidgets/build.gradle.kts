plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.app_air.widgets"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.fresco)
    implementation(libs.fresco.middleware)
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:WalletSDK"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
}
