plugins {
    id("org.mytonwallet.android.library")
    alias(libs.plugins.google.devtools.ksp)
}

android {
    namespace = "org.mytonwallet.app_air.walletsdk"
}

dependencies {
    ksp(libs.moshi.codegen)
    implementation(libs.moshi.core)
    implementation(libs.moshi.kotlin)
    implementation(libs.moshi.adapters)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
}
