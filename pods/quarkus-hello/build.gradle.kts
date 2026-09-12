plugins {
    id("java")
    alias(libs.plugins.spotless)
    id("io.quarkus") version "3.39.3"
}

repositories {
    mavenCentral()
    gradlePluginPortal()
}

val quarkusPlatformGroupId: String by project
val quarkusPlatformArtifactId: String by project
val quarkusPlatformVersion: String by project

dependencies {
    implementation(enforcedPlatform("${quarkusPlatformGroupId}:${quarkusPlatformArtifactId}:${quarkusPlatformVersion}"))
    implementation("io.quarkus:quarkus-rest")
    implementation("io.quarkus:quarkus-rest-jackson")
    implementation("io.quarkus:quarkus-kubernetes")
    implementation("io.quarkus:quarkus-kubernetes-config")
    implementation("io.quarkus:quarkus-kubernetes-client")
    implementation("io.quarkus:quarkus-kind")
    implementation("io.quarkus:quarkus-container-image-jib")
    implementation("io.quarkus:quarkus-container-image-docker")
    implementation("io.quarkus:quarkus-smallrye-health")
    implementation("io.quarkus:quarkus-arc")
    testImplementation("io.quarkus:quarkus-junit5")
    testImplementation("io.rest-assured:rest-assured")
}

group = "com.shadok.pods"
version = "1.0.0-SNAPSHOT"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

tasks.withType<Test> {
    useJUnitPlatform()
    systemProperty("java.util.logging.manager", "org.jboss.logmanager.LogManager")
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-parameters")
}

// Keep a complete mirror of reloadable application outputs, separate from runtime libraries.
val stageShadok by tasks.registering(Sync::class) {
    dependsOn(tasks.named("classes"), tasks.named("test"))
    into(layout.buildDirectory.dir("shadok-sync/dev/app"))
    from(sourceSets.main.get().output)
}

// Publication follows successful compilation and tests.
tasks.register<Exec>("shadokPublish") {
    group = "development"
    description = "Publish completed class/resource outputs to a Shadok session"
    dependsOn(stageShadok)
    workingDir(rootProject.projectDir)
    commandLine("shadok", "publish", "--config",
        rootProject.file("shadok.yaml").absolutePath, "--group", "quarkus-outputs")
}

// Spotless configuration
configure<com.diffplug.gradle.spotless.SpotlessExtension> {
    java {
        googleJavaFormat(libs.versions.google.java.format.get())
        removeUnusedImports()
        indentWithSpaces(4)
        trimTrailingWhitespace()
        endWithNewline()

        target("src/**/*.java")
    }

    format("markdown") {
        target("**/*.md")
        targetExclude("**/venv/**", "**/node_modules/**", "**/build/**", "**/target/**")
        prettier().config(mapOf(
            "parser" to "markdown",
            "proseWrap" to "always",
            "printWidth" to 80,
            "tabWidth" to 2
        ))
    }

    // Dockerfile formatting
    format("dockerfile") {
        target("**/Dockerfile*")
        targetExclude("**/venv/**", "**/node_modules/**", "**/build/**", "**/target/**")
        // Basic Dockerfile formatting
        indentWithSpaces(4)
        trimTrailingWhitespace()
        endWithNewline()
    }

    // Shell script formatting
    format("shell") {
        target("**/*.sh")
        targetExclude("**/venv/**", "**/node_modules/**", "**/build/**", "**/target/**")
        // Basic shell script formatting
        indentWithSpaces(2)
        trimTrailingWhitespace()
        endWithNewline()
    }

    // Basic TOML formatting without additional formatter dependencies
    format("toml") {
        target("**/*.toml")
        targetExclude("**/venv/**", "**/node_modules/**", "**/build/**", "**/target/**")
        // Use consistent indentation
        indentWithSpaces(2)
        trimTrailingWhitespace()
        endWithNewline()
    }
}
