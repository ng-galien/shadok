rootProject.name = "shadok-parent"

include("shadok")

pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
    
    plugins {
        id("io.quarkus") version "3.23.2"
        id("com.diffplug.spotless") version "6.25.0"
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}
