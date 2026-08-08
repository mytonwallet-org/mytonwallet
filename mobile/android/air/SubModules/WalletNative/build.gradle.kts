plugins {
    id("org.mytonwallet.android.library")
}

android {
    namespace = "org.mytonwallet.n.utils"

    ndkVersion = "27.3.13750724"

    defaultConfig {
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path("jni/CMakeLists.txt")
        }
    }
}

dependencies {
}
