plugins {
    `java-platform`
    id("com.diffplug.spotless") version "6.25.0" apply false
}

description = "Shadok Parent - BOM for dependency management"

javaPlatform {
    allowDependencies()
}

dependencies {
    // Import external BOMs
    api(platform("io.quarkus.platform:quarkus-bom:${findProperty("quarkusVersion")}"))
    api(platform("io.quarkiverse.operatorsdk:quarkus-operator-sdk-bom:${findProperty("quarkusOperatorSdkVersion")}"))
    
    constraints {
        // Additional dependencies
        api("io.javaoperatorsdk:kubernetes-webhooks-framework-core:${findProperty("josdkWebhooksVersion")}")
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
            languageVersion.set(JavaLanguageVersion.of(findProperty("javaVersion") as String))
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
            googleJavaFormat("1.19.2")
            removeUnusedImports()
            target("src/**/*.java")
        }
    }
    
    // Compilation configuration
    tasks.withType<JavaCompile> {
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-parameters"))
    }
}
