plugins {
    `java-platform`
    alias(libs.plugins.spotless) apply false
}

description = "Shadok Parent - BOM for dependency management"

javaPlatform {
    allowDependencies()
}

dependencies {
    // Import external BOMs
    api(platform(libs.quarkus.bom))
    api(platform(libs.quarkus.operator.sdk.bom))
    
    constraints {
        // Additional dependencies
        api(libs.kubernetes.webhooks.core)
    }
}

// Subprojects configuration
subprojects {
    apply(plugin = "java")
    apply(plugin = "java-library")
    apply(plugin = "com.diffplug.spotless")
    
    group = findProperty("group") as String
    version = findProperty("version") as String
    
    configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
        withSourcesJar()
    }
    
    // Common repositories
    repositories {
        mavenCentral()
    }
    
    // Common test configuration
    tasks.withType<Test> {
        useJUnitPlatform()
        systemProperty("java.util.logging.manager", "org.jboss.logmanager.LogManager")
        // jvmArgs("-XX:+StartFlightRecording")  // Disabled due to JVM compatibility issues
    }
    
    // Spotless configuration
    configure<com.diffplug.gradle.spotless.SpotlessExtension> {
        java {
            googleJavaFormat(libs.versions.google.java.format.get())
            removeUnusedImports()
            target("src/**/*.java")
        }
        
        format("toml") {
            target("**/*.toml")
            prettier()
        }
    }
    
    // Compilation configuration
    tasks.withType<JavaCompile> {
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-parameters"))
    }
}
