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
// file_picker's own AGP-version check (isAgp9OrAbove) skips applying the Kotlin
// plugin on AGP 9+ regardless of this project's `android.builtInKotlin=false`
// setting, so its .kt sources never get compiled and GeneratedPluginRegistrant
// fails with "cannot find symbol FilePickerPlugin".
// See https://github.com/miguelpruivo/flutter_file_picker/issues/1942
//
// Applied eagerly (not from afterEvaluate) and before evaluationDependsOn(":app")
// below. The Kotlin Gradle Plugin's own KotlinPluginLifecycle tracks each
// project's configuration stage independently of Gradle's; applying it from an
// afterEvaluate callback fires too late once evaluationDependsOn(":app") has
// pulled :app's evaluation forward, causing
// "KotlinPluginLifecycle cannot be started in ProjectState 'EXECUTING'".
// Applying it here runs as part of file_picker's normal configuration, before
// its own build.gradle executes, which is the ordering the lifecycle expects.
subprojects {
    if (name == "file_picker" && extensions.findByName("kotlin") == null) {
        pluginManager.apply("org.jetbrains.kotlin.android")
        extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
