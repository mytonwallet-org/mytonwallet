plugins {
    id("org.mytonwallet.android.library")
    alias(libs.plugins.google.devtools.ksp)
}

android {
    namespace = "org.mytonwallet.app_air.walletcore"
}

val airSubModulePath = project.property("airSubModulePath")

dependencies {
    ksp(libs.moshi.codegen)
    implementation(libs.moshi.core)
    implementation(libs.moshi.kotlin)
    implementation(libs.moshi.adapters)
    implementation(libs.kotlin.reflect)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.webkit)
    implementation(libs.firebase.messaging)
    implementation(libs.tweetnacl)
    implementation(project("$airSubModulePath:WalletContext"))
    implementation(project("$airSubModulePath:WalletBaseContext"))
    implementation(project("$airSubModulePath:Icons"))
    implementation(project("$airSubModulePath:NativeEnclave"))
}
