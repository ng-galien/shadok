package org.shadok.operator.model;

/**
 * Enum representing supported application types combining framework and build system.
 *
 * <p>This enum provides precise application categorization by combining the framework/runtime with
 * the specific build system, enabling intelligent build optimization and caching strategies.
 *
 * <p>Format: FRAMEWORK_BUILDSYSTEM (e.g., QUARKUS_GRADLE, SPRING_MAVEN, NODE_NPM)
 */
public enum ApplicationType {
  // ========================================
  // 🌱 JVM Ecosystem
  // ========================================

  /** Quarkus applications with Maven build system */
  QUARKUS_MAVEN("Quarkus", "java", "maven", "jar,native"),

  /** Quarkus applications with Gradle build system */
  QUARKUS_GRADLE("Quarkus", "java", "gradle", "jar,native"),

  /** Spring Boot applications with Maven build system */
  SPRING_MAVEN("Spring Boot", "java", "maven", "jar,war"),

  /** Spring Boot applications with Gradle build system */
  SPRING_GRADLE("Spring Boot", "java", "gradle", "jar,war"),

  /** Traditional Java applications with Maven */
  JAVA_MAVEN("Java", "java", "maven", "jar,war"),

  /** Traditional Java applications with Gradle */
  JAVA_GRADLE("Java", "java", "gradle", "jar,war"),

  // ========================================
  // 🌐 JavaScript/Node.js Ecosystem
  // ========================================

  /** Node.js applications with NPM package manager */
  NODE_NPM("Node.js", "javascript", "npm", "js,ts"),

  /** Node.js applications with Yarn package manager */
  NODE_YARN("Node.js", "javascript", "yarn", "js,ts"),

  /** React applications with NPM */
  REACT_NPM("React", "javascript", "npm", "bundle"),

  /** React applications with Yarn */
  REACT_YARN("React", "javascript", "yarn", "bundle"),

  /** Next.js applications with NPM */
  NEXTJS_NPM("Next.js", "javascript", "npm", "bundle"),

  /** Next.js applications with Yarn */
  NEXTJS_YARN("Next.js", "javascript", "yarn", "bundle"),

  /** Vue.js applications with NPM */
  VUE_NPM("Vue.js", "javascript", "npm", "bundle"),

  /** Vue.js applications with Yarn */
  VUE_YARN("Vue.js", "javascript", "yarn", "bundle"),

  /** Angular applications with NPM */
  ANGULAR_NPM("Angular", "typescript", "npm", "bundle"),

  /** Angular applications with Yarn */
  ANGULAR_YARN("Angular", "typescript", "yarn", "bundle"),

  // ========================================
  // 🐍 Python Ecosystem
  // ========================================

  /** Python applications with pip package manager */
  PYTHON_PIP("Python", "python", "pip", "wheel"),

  /** Python applications with Poetry dependency manager */
  PYTHON_POETRY("Python", "python", "poetry", "wheel"),

  /** Django web applications with pip */
  DJANGO_PIP("Django", "python", "pip", "wheel"),

  /** Django web applications with Poetry */
  DJANGO_POETRY("Django", "python", "poetry", "wheel"),

  /** FastAPI applications with pip */
  FASTAPI_PIP("FastAPI", "python", "pip", "wheel"),

  /** FastAPI applications with Poetry */
  FASTAPI_POETRY("FastAPI", "python", "poetry", "wheel"),

  // ========================================
  // 🦀 Systems Languages
  // ========================================

  /** Go applications with Go modules */
  GO_MOD("Go", "go", "go-mod", "binary"),

  /** Rust applications with Cargo */
  RUST_CARGO("Rust", "rust", "cargo", "binary"),

  // ========================================
  // 💎 Other Ecosystems
  // ========================================

  /** .NET applications with NuGet */
  DOTNET_NUGET("ASP.NET Core", "csharp", "dotnet", "dll,exe"),

  /** PHP applications with Composer */
  PHP_COMPOSER("PHP", "php", "composer", "phar"),

  /** Ruby applications with Bundler */
  RUBY_BUNDLER("Ruby", "ruby", "bundler", "gem"),

  /** Ruby on Rails applications with Bundler */
  RAILS_BUNDLER("Ruby on Rails", "ruby", "bundler", "gem"),

  /** Flutter applications with Pub */
  FLUTTER_PUB("Flutter", "dart", "pub", "apk,ipa,web"),

  // ========================================
  // �️ Custom Applications
  // ========================================

  /** Custom application type with user-defined build commands */
  CUSTOM("Custom", "unknown", "custom", "custom");

  // ========================================
  // 📊 Metadata for Build Intelligence
  // ========================================

  private final String displayName;
  private final String primaryLanguage;
  private final String buildSystem;
  private final String artifactTypes;

  ApplicationType(
      String displayName, String primaryLanguage, String buildSystem, String artifactTypes) {
    this.displayName = displayName;
    this.primaryLanguage = primaryLanguage;
    this.buildSystem = buildSystem;
    this.artifactTypes = artifactTypes;
  }

  /**
   * Get the human-readable display name.
   *
   * @return display name for UI/logs
   */
  public String getDisplayName() {
    return displayName;
  }

  /**
   * Get the primary programming language.
   *
   * @return primary language (java, python, javascript, etc.)
   */
  public String getPrimaryLanguage() {
    return primaryLanguage;
  }

  /**
   * Get the build system for this application type.
   *
   * @return build system (maven, gradle, npm, etc.)
   */
  public String getBuildSystem() {
    return buildSystem;
  }

  /**
   * Get produced artifact types as comma-separated string.
   *
   * @return artifact types (jar,binary,bundle, etc.)
   */
  public String getArtifactTypes() {
    return artifactTypes;
  }

  /**
   * Check if this is a JVM-based application.
   *
   * @return true if JVM-based
   */
  public boolean isJvmBased() {
    return primaryLanguage.equals("java");
  }

  /**
   * Check if this is a Node.js ecosystem application.
   *
   * @return true if Node.js-based
   */
  public boolean isNodeBased() {
    return primaryLanguage.equals("javascript")
        || primaryLanguage.equals("typescript")
        || buildSystem.equals("npm")
        || buildSystem.equals("yarn");
  }

  /**
   * Check if this is a Python ecosystem application.
   *
   * @return true if Python-based
   */
  public boolean isPythonBased() {
    return primaryLanguage.equals("python");
  }

  /**
   * Get recommended cache size based on application type.
   *
   * @return recommended cache size in GB
   */
  public int getRecommendedCacheSize() {
    return switch (this) {
      case QUARKUS_MAVEN, QUARKUS_GRADLE, SPRING_MAVEN, SPRING_GRADLE, JAVA_MAVEN, JAVA_GRADLE -> 4;
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
          2;
      case PYTHON_PIP, PYTHON_POETRY, DJANGO_PIP, DJANGO_POETRY, FASTAPI_PIP, FASTAPI_POETRY -> 1;
      case GO_MOD, RUST_CARGO -> 1;
      case DOTNET_NUGET -> 2;
      case FLUTTER_PUB -> 2;
      case PHP_COMPOSER, RUBY_BUNDLER, RAILS_BUNDLER -> 1;
      case CUSTOM -> 2; // Conservative default for custom
    };
  }

  /**
   * Get common dependency cache paths for this application type.
   *
   * @return array of cache paths
   */
  public String[] getCommonCachePaths() {
    return switch (this) {
      case QUARKUS_MAVEN, SPRING_MAVEN, JAVA_MAVEN -> new String[] {"/root/.m2/repository"};
      case QUARKUS_GRADLE, SPRING_GRADLE, JAVA_GRADLE -> new String[] {"/root/.gradle/caches"};
      case NODE_NPM, REACT_NPM, NEXTJS_NPM, VUE_NPM, ANGULAR_NPM -> new String[] {"/root/.npm"};
      case NODE_YARN, REACT_YARN, NEXTJS_YARN, VUE_YARN, ANGULAR_YARN ->
          new String[] {"/root/.yarn/cache"};
      case PYTHON_PIP, DJANGO_PIP, FASTAPI_PIP -> new String[] {"/root/.cache/pip"};
      case PYTHON_POETRY, DJANGO_POETRY, FASTAPI_POETRY -> new String[] {"/root/.cache/pypoetry"};
      case GO_MOD -> new String[] {"/go/pkg/mod"};
      case RUST_CARGO -> new String[] {"/usr/local/cargo/registry"};
      case DOTNET_NUGET -> new String[] {"/root/.nuget/packages"};
      case PHP_COMPOSER -> new String[] {"/root/.composer/cache"};
      case RUBY_BUNDLER, RAILS_BUNDLER -> new String[] {"/usr/local/bundle"};
      case FLUTTER_PUB -> new String[] {"/root/.pub-cache"};
      case CUSTOM -> new String[] {"/cache"};
    };
  }

  /**
   * Get the framework name (without build system).
   *
   * @return framework name
   */
  public String getFramework() {
    return switch (this) {
      case QUARKUS_MAVEN, QUARKUS_GRADLE -> "Quarkus";
      case SPRING_MAVEN, SPRING_GRADLE -> "Spring Boot";
      case JAVA_MAVEN, JAVA_GRADLE -> "Java";
      case NODE_NPM, NODE_YARN -> "Node.js";
      case REACT_NPM, REACT_YARN -> "React";
      case NEXTJS_NPM, NEXTJS_YARN -> "Next.js";
      case VUE_NPM, VUE_YARN -> "Vue.js";
      case ANGULAR_NPM, ANGULAR_YARN -> "Angular";
      case PYTHON_PIP, PYTHON_POETRY -> "Python";
      case DJANGO_PIP, DJANGO_POETRY -> "Django";
      case FASTAPI_PIP, FASTAPI_POETRY -> "FastAPI";
      case GO_MOD -> "Go";
      case RUST_CARGO -> "Rust";
      case DOTNET_NUGET -> "ASP.NET Core";
      case PHP_COMPOSER -> "PHP";
      case RUBY_BUNDLER -> "Ruby";
      case RAILS_BUNDLER -> "Ruby on Rails";
      case FLUTTER_PUB -> "Flutter";
      case CUSTOM -> "Custom";
    };
  }
}
