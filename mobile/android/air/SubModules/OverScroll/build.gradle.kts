plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "me.everything.android.ui.overscroll"
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
}
