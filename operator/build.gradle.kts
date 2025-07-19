plugins {
    java
    alias(libs.plugins.quarkus)
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

description = "Shadok - Kubernetes Live Development Operator"

dependencies {
    // Import external BOMs
    implementation(platform(project(":")))

    // Quarkus dependencies (using bundles)
    implementation(libs.bundles.quarkus.core)

    // TLS support for webhooks
    implementation("io.quarkus:quarkus-vertx-http")
    implementation("io.quarkus:quarkus-tls-registry")

    // Kubernetes dependencies (using bundles)
    implementation(libs.bundles.operator)

    // Jackson for JSON processing
    implementation(libs.jackson.annotations)
    implementation("io.quarkus:quarkus-container-image-jib")
    implementation("io.quarkus:quarkus-smallrye-health")

    // Test dependencies (using bundles)
    testImplementation(libs.bundles.testing)
}

tasks.withType<Test> {
    systemProperty("maven.home", System.getProperty("maven.home"))
}

// Copy helm directory into the build output
tasks.register<ProcessResources>("copyHelm") {
    into("build/chart/operator")
    from("src/main/chart/operator") {
        include("Chart.yaml", "values.yaml")
        expand(
            "chartName" to project.extra["chartName"],
            "chartVersion" to project.extra["chartVersion"],
            "chartDescription" to project.extra["chartDescription"],
            "operatorVersion" to project.version,
            "imageRegistry" to project.extra["imageRegistry"],
            "imageName" to project.extra["imageName"],
            "imageTag" to project.extra["imageTag"]
        )
    }
    from("src/main/chart/operator") {
        exclude("Chart.yaml", "values.yaml")
    }
}

// Copy helm directory into the build output
tasks.register<ProcessResources>("copyCrds") {
    into("build/chart/operator/crds")
    from("build/kubernetes") {
        exclude("kubernetes.json", "kubernetes.yml")
    }
}

tasks.named("build") {
    dependsOn("copyHelm")
    dependsOn("copyCrds")
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

quarkus {
    buildForkOptions {
        systemProperty("quarkus.container-image.build", "true")
        systemProperty("quarkus.container-image.push", "true")
        systemProperty("quarkus.container-image.registry", project.extra["imageRegistry"])
        systemProperty("quarkus.container-image.group", "")
        systemProperty("quarkus.container-image.name", project.extra["imageName"])
        systemProperty("quarkus.container-image.tag", project.extra["imageTag"])
        systemProperty("quarkus.container-image.insecure",
            (findProperty("env") as String) == "kind"
        )
        //systemProperty("quarkus.operator-sdk.crd.output-directory", "crds")
    }
}

