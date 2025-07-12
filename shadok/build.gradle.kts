plugins {
    java
    id("io.quarkus")
}

description = "Shadok - Kubernetes Live Development Operator"

dependencies {
    // Import parent BOM for version management
    implementation(platform(project(":")))
    
    // Quarkus dependencies
    implementation("io.quarkus:quarkus-arc")
    implementation("io.quarkus:quarkus-rest")
    implementation("io.quarkiverse.operatorsdk:quarkus-operator-sdk")
    
    // Kubernetes client
    implementation("io.fabric8:kubernetes-client")
    
    // Jackson for JSON processing
    implementation("com.fasterxml.jackson.core:jackson-annotations")
    
    // Webhook framework
    implementation("io.javaoperatorsdk:kubernetes-webhooks-framework-core")
    
    // Test dependencies
    testImplementation("io.quarkus:quarkus-junit5")
    testImplementation("io.rest-assured:rest-assured")
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
