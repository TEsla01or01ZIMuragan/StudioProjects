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

subprojects {
    val configureCompileSdk = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val compileSdkVersionMethod = android.javaClass.methods.firstOrNull {
                    it.name == "compileSdkVersion" && it.parameterTypes.size == 1 && it.parameterTypes[0] == Int::class.javaPrimitiveType
                }
                if (compileSdkVersionMethod != null) {
                    compileSdkVersionMethod.invoke(android, 34)
                } else {
                    val setCompileSdkMethod = android.javaClass.methods.firstOrNull {
                        it.name == "setCompileSdk" && it.parameterTypes.size == 1
                    }
                    setCompileSdkMethod?.invoke(android, 34)
                }
            } catch (_: Exception) {}
        }
    }

    if (project.state.executed) {
        configureCompileSdk()
    } else {
        project.afterEvaluate {
            configureCompileSdk()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
