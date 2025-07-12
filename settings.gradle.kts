rootProject.name = "shadok-parent"

include("shadok")

pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
    
    val quarkusVersion: String by settings
    val spotlessVersion: String by settings
    
    plugins {
        id("io.quarkus") version quarkusVersion
        id("com.diffplug.spotless") version spotlessVersion
        kotlin("jvm") version "1.9.24"
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}
