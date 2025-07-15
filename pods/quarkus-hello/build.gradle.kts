plugins {
    id("java")
    id("io.quarkus") version "3.8.1"
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
    implementation("io.quarkus:quarkus-resteasy-reactive")
    implementation("io.quarkus:quarkus-resteasy-reactive-jackson")
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
    systemProperty("java.util.logging.manager", "org.jboss.logmanager.LogManager")
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.compilerArgs.add("-parameters")
}
