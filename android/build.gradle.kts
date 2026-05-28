allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all subprojects (plugins) to use Java 17 to suppress
// "source/target value 8 is obsolete" warnings from the Java compiler
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        // Also suppress the Xlint:options warning via compiler args
        tasks.withType<JavaCompile>().configureEach {
            options.compilerArgs.addAll(listOf(
                "-Xlint:-options",
                "-Xlint:-deprecation",
                "-Xlint:none"   // suppress all lint notes from plugin sources
            ))
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
