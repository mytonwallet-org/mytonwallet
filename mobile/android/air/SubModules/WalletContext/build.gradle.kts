plugins {
    id("org.mytonwallet.android.library")
    alias(libs.plugins.google.devtools.ksp)
}

android {
    namespace = "org.mytonwallet.app_air.walletcontext"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    ksp(libs.moshi.codegen)
    implementation(libs.moshi.core)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.biometric)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.material)
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
}
