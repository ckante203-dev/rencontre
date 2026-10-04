// 1. TOUJOURS EN PREMIER : Configuration des outils de build
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Le connecteur pour les services Google (Firebase)
        classpath("com.google.gms:google-services:4.4.2")
        // Crashlytics : rapports de plantage (console Firebase)
        classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.2")
    }
}

// 2. Configuration des dépôts pour tous les modules
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 3. Gestion personnalisée du répertoire de build (ton code spécifique)
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

// 4. Tâche de nettoyage
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}