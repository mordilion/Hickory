allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker's own AGP-version check (isAgp9OrAbove) skips applying the Kotlin
// plugin on AGP 9+ regardless of this project's `android.builtInKotlin=false`
// setting, so its .kt sources never get compiled and GeneratedPluginRegistrant
// fails with "cannot find symbol FilePickerPlugin".
// See https://github.com/miguelpruivo/flutter_file_picker/issues/1942
subprojects {
    afterEvaluate {
        if (name == "file_picker" && extensions.findByName("kotlin") == null) {
            pluginManager.apply("org.jetbrains.kotlin.android")
            extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
