plugins {
    java
    alias(libs.plugins.quarkus)
}

description = "Shadok - Kubernetes Live Development Operator"

dependencies {
    // Import parent BOM for version management
    implementation(platform(project(":")))
    
    // Quarkus dependencies (using bundles)
    implementation(libs.bundles.quarkus.core)
    implementation(libs.quarkus.operator.sdk)
    implementation(libs.quarkus.container.image.docker)
    
    // Kubernetes dependencies (using bundles)
    implementation(libs.bundles.kubernetes)
    
    // Jackson for JSON processing
    implementation(libs.jackson.annotations)
    
    // Test dependencies (using bundles)
    testImplementation(libs.bundles.testing)
}

quarkus {
    // Native build configuration
    // nativeBuilder = "buildkit"  // TODO: Fix syntax
}

tasks.withType<Test> {
    systemProperty("maven.home", System.getProperty("maven.home"))
}

// Native build profile
if (project.hasProperty("native")) {
    tasks.named("test") {
        enabled = false
    }
    
    tasks.named("quarkusIntTest") {
        enabled = true
    }
}
