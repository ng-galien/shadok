package org.shadok.operator.model.application;

import java.util.Map;
import java.util.Set;
import org.shadok.operator.model.ApplicationType;

/**
 * Helper utility for ApplicationType-specific logic and optimizations.
 *
 * <p>This class provides intelligent defaults and recommendations based on the application type to
 * optimize build performance, caching strategies, and resource allocation.
 */
public final class ApplicationTypeHelper {

  private ApplicationTypeHelper() {
    // Utility class
  }

  /**
   * Generate intelligent labels based on application type.
   *
   * @param applicationType the application type
   * @return map of recommended labels
   */
  public static Map<String, String> generateIntelligentLabels(ApplicationType applicationType) {
    return Map.of(
        "app.kubernetes.io/name", "shadok-application",
        "app.kubernetes.io/component", getComponentType(applicationType),
        "app.kubernetes.io/part-of", "shadok-platform",
        "shadok.org/language", applicationType.getPrimaryLanguage(),
        "shadok.org/build-system", applicationType.getBuildSystem(),
        "shadok.org/cache-strategy", getCacheStrategy(applicationType));
  }

  /**
   * Get the Kubernetes component type for the application.
   *
   * @param applicationType the application type
   * @return component type
   */
  public static String getComponentType(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN,
              QUARKUS_GRADLE,
              SPRING_MAVEN,
              SPRING_GRADLE,
              JAVA_MAVEN,
              JAVA_GRADLE,
              DOTNET_NUGET ->
          "microservice";
      case NODE_NPM,
              NODE_YARN,
              PYTHON_PIP,
              PYTHON_POETRY,
              DJANGO_PIP,
              DJANGO_POETRY,
              FASTAPI_PIP,
              FASTAPI_POETRY,
              GO_MOD,
              RUST_CARGO ->
          "service";
      case REACT_NPM,
              REACT_YARN,
              NEXTJS_NPM,
              NEXTJS_YARN,
              VUE_NPM,
              VUE_YARN,
              ANGULAR_NPM,
              ANGULAR_YARN ->
          "frontend";
      case RAILS_BUNDLER, PHP_COMPOSER, RUBY_BUNDLER -> "web-application";
      case FLUTTER_PUB -> "mobile-app";
      case CUSTOM -> "application";
    };
  }

  /**
   * Get the caching strategy for the application type.
   *
   * @param applicationType the application type
   * @return cache strategy
   */
  public static String getCacheStrategy(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN, QUARKUS_GRADLE, SPRING_MAVEN, SPRING_GRADLE, JAVA_MAVEN, JAVA_GRADLE ->
          "jvm-deps";
      case NODE_NPM, REACT_NPM, NEXTJS_NPM, VUE_NPM, ANGULAR_NPM -> "npm-modules";
      case NODE_YARN, REACT_YARN, NEXTJS_YARN, VUE_YARN, ANGULAR_YARN -> "yarn-modules";
      case PYTHON_PIP, DJANGO_PIP, FASTAPI_PIP -> "pip-packages";
      case PYTHON_POETRY, DJANGO_POETRY, FASTAPI_POETRY -> "poetry-packages";
      case GO_MOD -> "go-modules";
      case RUST_CARGO -> "cargo-registry";
      case RUBY_BUNDLER, RAILS_BUNDLER -> "gem-bundle";
      case PHP_COMPOSER -> "composer-vendor";
      case DOTNET_NUGET -> "nuget-packages";
      case FLUTTER_PUB -> "pub-cache";
      case CUSTOM -> "generic";
    };
  }

  /**
   * Get recommended init container mounts for the application type.
   *
   * @param applicationType the application type
   * @return set of recommended mount paths
   */
  public static Set<String> getRecommendedInitMounts(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN, SPRING_MAVEN, JAVA_MAVEN ->
          Set.of("/workspace/src", "/workspace/pom.xml");
      case QUARKUS_GRADLE, SPRING_GRADLE, JAVA_GRADLE ->
          Set.of("/workspace/src", "/workspace/build.gradle", "/workspace/gradle.properties");
      case NODE_NPM,
              NODE_YARN,
              REACT_NPM,
              REACT_YARN,
              NEXTJS_NPM,
              NEXTJS_YARN,
              VUE_NPM,
              VUE_YARN,
              ANGULAR_NPM,
              ANGULAR_YARN ->
          Set.of(
              "/workspace/src",
              "/workspace/package.json",
              "/workspace/package-lock.json",
              "/workspace/yarn.lock");
      case PYTHON_PIP, DJANGO_PIP, FASTAPI_PIP ->
          Set.of("/workspace/src", "/workspace/requirements.txt", "/workspace/setup.py");
      case PYTHON_POETRY, DJANGO_POETRY, FASTAPI_POETRY ->
          Set.of("/workspace/src", "/workspace/pyproject.toml");
      case GO_MOD -> Set.of("/workspace/src", "/workspace/go.mod", "/workspace/go.sum");
      case RUST_CARGO -> Set.of("/workspace/src", "/workspace/Cargo.toml", "/workspace/Cargo.lock");
      case RUBY_BUNDLER, RAILS_BUNDLER ->
          Set.of("/workspace/src", "/workspace/Gemfile", "/workspace/Gemfile.lock");
      case PHP_COMPOSER ->
          Set.of("/workspace/src", "/workspace/composer.json", "/workspace/composer.lock");
      case DOTNET_NUGET -> Set.of("/workspace/src", "/workspace/*.csproj", "/workspace/*.sln");
      case FLUTTER_PUB ->
          Set.of("/workspace/lib", "/workspace/pubspec.yaml", "/workspace/pubspec.lock");
      case CUSTOM -> Set.of("/workspace/src");
    };
  }

  /**
   * Generate build environment variables based on application type.
   *
   * @param applicationType the application type
   * @return map of environment variables
   */
  public static Map<String, String> getBuildEnvironmentVariables(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN, SPRING_MAVEN, JAVA_MAVEN ->
          Map.of(
              "JAVA_HOME", "/usr/lib/jvm/java-21-openjdk",
              "MAVEN_OPTS", "-Xmx2g -Dmaven.repo.local=/cache/.m2/repository");
      case QUARKUS_GRADLE, SPRING_GRADLE, JAVA_GRADLE ->
          Map.of(
              "JAVA_HOME", "/usr/lib/jvm/java-21-openjdk",
              "GRADLE_USER_HOME", "/cache/.gradle");
      case NODE_NPM, REACT_NPM, NEXTJS_NPM, VUE_NPM, ANGULAR_NPM ->
          Map.of(
              "NODE_ENV", "production",
              "NPM_CONFIG_CACHE", "/cache/.npm");
      case NODE_YARN, REACT_YARN, NEXTJS_YARN, VUE_YARN, ANGULAR_YARN ->
          Map.of(
              "NODE_ENV", "production",
              "YARN_CACHE_FOLDER", "/cache/.yarn");
      case PYTHON_PIP, DJANGO_PIP, FASTAPI_PIP ->
          Map.of(
              "PYTHONPATH", "/workspace",
              "PIP_CACHE_DIR", "/cache/.pip");
      case PYTHON_POETRY, DJANGO_POETRY, FASTAPI_POETRY ->
          Map.of(
              "PYTHONPATH", "/workspace",
              "POETRY_CACHE_DIR", "/cache/.poetry");
      case GO_MOD ->
          Map.of(
              "GOCACHE", "/cache/.go-build",
              "GOMODCACHE", "/cache/go/pkg/mod");
      case RUST_CARGO ->
          Map.of(
              "CARGO_HOME", "/cache/.cargo",
              "CARGO_TARGET_DIR", "/cache/target");
      case RUBY_BUNDLER, RAILS_BUNDLER ->
          Map.of(
              "BUNDLE_PATH", "/cache/.bundle",
              "GEM_HOME", "/cache/.gem");
      case PHP_COMPOSER ->
          Map.of(
              "COMPOSER_CACHE_DIR", "/cache/.composer",
              "COMPOSER_HOME", "/cache/.composer");
      case DOTNET_NUGET ->
          Map.of(
              "NUGET_PACKAGES", "/cache/.nuget/packages",
              "DOTNET_CLI_TELEMETRY_OPTOUT", "1");
      case FLUTTER_PUB ->
          Map.of(
              "PUB_CACHE", "/cache/.pub-cache",
              "FLUTTER_ROOT", "/opt/flutter");
      case CUSTOM -> Map.of("BUILD_CACHE", "/cache");
    };
  }

  /**
   * Get the recommended base image for building this application type.
   *
   * @param applicationType the application type
   * @return base image name
   */
  public static String getRecommendedBaseImage(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN, QUARKUS_GRADLE, SPRING_MAVEN, SPRING_GRADLE -> "eclipse-temurin:21-jdk";
      case JAVA_MAVEN, JAVA_GRADLE -> "eclipse-temurin:17-jdk";
      case NODE_NPM, NODE_YARN, REACT_NPM, REACT_YARN, NEXTJS_NPM, NEXTJS_YARN, VUE_NPM, VUE_YARN ->
          "node:20-alpine";
      case ANGULAR_NPM, ANGULAR_YARN -> "node:18-alpine";
      case PYTHON_PIP, PYTHON_POETRY, DJANGO_PIP, DJANGO_POETRY, FASTAPI_PIP, FASTAPI_POETRY ->
          "python:3.11-slim";
      case GO_MOD -> "golang:1.21-alpine";
      case RUST_CARGO -> "rust:1.70-slim";
      case RUBY_BUNDLER, RAILS_BUNDLER -> "ruby:3.2-alpine";
      case PHP_COMPOSER -> "php:8.2-fpm-alpine";
      case DOTNET_NUGET -> "mcr.microsoft.com/dotnet/sdk:8.0";
      case FLUTTER_PUB -> "cirrusci/flutter:stable";
      case CUSTOM -> "ubuntu:22.04";
    };
  }

  /**
   * Check if the application type supports hot reload during development.
   *
   * @param applicationType the application type
   * @return true if hot reload is supported
   */
  public static boolean supportsHotReload(ApplicationType applicationType) {
    return switch (applicationType) {
      case QUARKUS_MAVEN, QUARKUS_GRADLE -> true; // Quarkus live reload
      case SPRING_MAVEN, SPRING_GRADLE -> true; // Spring DevTools
      case NODE_NPM,
              NODE_YARN,
              REACT_NPM,
              REACT_YARN,
              NEXTJS_NPM,
              NEXTJS_YARN,
              VUE_NPM,
              VUE_YARN,
              ANGULAR_NPM,
              ANGULAR_YARN ->
          true; // Webpack HMR, Vite
      case PYTHON_PIP, PYTHON_POETRY, DJANGO_PIP, DJANGO_POETRY -> true; // Django runserver
      case FASTAPI_PIP, FASTAPI_POETRY -> true; // Uvicorn reload
      case RAILS_BUNDLER -> true; // Rails development server
      case PHP_COMPOSER -> true; // PHP built-in server
      case DOTNET_NUGET -> true; // .NET hot reload
      case FLUTTER_PUB -> true; // Flutter hot reload
      case JAVA_MAVEN, JAVA_GRADLE, GO_MOD, RUST_CARGO, RUBY_BUNDLER -> false;
      case CUSTOM -> false; // Unknown capability
    };
  }
}
