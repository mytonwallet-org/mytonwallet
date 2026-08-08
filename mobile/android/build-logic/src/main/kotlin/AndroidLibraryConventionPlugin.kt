import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.GradleException
import org.gradle.api.JavaVersion
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.dependencies
import org.gradle.kotlin.dsl.getByType
import org.gradle.kotlin.dsl.named
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

class AndroidLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) = with(target) {
        pluginManager.apply("com.android.library")
        pluginManager.apply("org.jetbrains.kotlin.android")

        extensions.configure<LibraryExtension> {
            compileSdk = (rootProject.property("compileSdkVersion") as Number).toInt()

            defaultConfig {
                minSdk = (rootProject.property("minSdkVersion") as Number).toInt()
                testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

                val consumerRules = layout.projectDirectory.file("consumer-rules.pro").asFile
                if (consumerRules.exists()) {
                    consumerProguardFiles(consumerRules)
                }
            }

            buildTypes.named("release") {
                isMinifyEnabled = false
                proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro"
                )
            }

            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_1_8
                targetCompatibility = JavaVersion.VERSION_1_8
            }

            lint {
                abortOnError = true
                checkReleaseBuilds = true
            }
        }

        extensions.configure<KotlinAndroidProjectExtension> {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_1_8)
                suppressWarnings.set(false)
            }
        }

        val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")
        dependencies {
            add("testImplementation", libs.findLibrary("junit").get())
            add("androidTestImplementation", libs.findLibrary("androidx-junit").get())
            add("androidTestImplementation", libs.findLibrary("androidx-espresso-core").get())
        }

        afterEvaluate {
            val duplicates = buildFile.readLines()
                .mapNotNull(dependencyDeclaration::matchEntire)
                .map { match ->
                    val configuration = match.groupValues[1]
                    val notation = match.groupValues[2].replace(whitespace, "")
                    "$configuration($notation)"
                }
                .groupingBy { it }
                .eachCount()
                .filterValues { it > 1 }
                .keys

            if (duplicates.isNotEmpty()) {
                throw GradleException(
                    "Duplicate dependencies declared in $path:\n${duplicates.joinToString("\n") { "- $it" }}"
                )
            }
        }
    }

    private companion object {
        val dependencyDeclaration = Regex(
            """\s*(api|implementation|compileOnly|runtimeOnly|testImplementation|androidTestImplementation|ksp|kapt|annotationProcessor|[A-Za-z0-9]+(?:Api|Implementation|CompileOnly|RuntimeOnly|Ksp|Kapt|AnnotationProcessor))\((.+)\)\s*"""
        )
        val whitespace = Regex("""\s+""")
    }
}
