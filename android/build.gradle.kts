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

    // IMPORTANTE:
    // Registrar afterEvaluate ANTES de evaluationDependsOn
    afterEvaluate {

        val androidExtension = extensions.findByName("android")

        if (androidExtension != null) {

            configure<com.android.build.gradle.BaseExtension> {

                // Fuerza compileSdk para plugins Flutter
                compileSdkVersion(35)

                // Opcional
                // buildToolsVersion("35.0.0")
            }
        }
    }

    // Debe ir DESPUÉS
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
