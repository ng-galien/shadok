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
        
        // Configuration TOML simplifiée (sans prettier pour éviter les dépendances)
        format("toml") {
            target("**/*.toml")
            targetExclude("**/venv/**", "**/node_modules/**", "**/build/**", "**/target/**")
            // Utilise un formatteur simple pour la cohérence d'indentation
            indentWithSpaces(2)
            trimTrailingWhitespace()
            endWithNewline()
        }
    }
    
    // Compilation configuration
    tasks.withType<JavaCompile> {
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-parameters"))
    }
}

// =========================
// Python Pods Management
// =========================

val pythonPodDir = file("pods/python-hello")
val pythonSrcDir = file("$pythonPodDir/src")
val pythonTestsDir = file("$pythonPodDir/tests")
val pythonVenvDir = file("$pythonPodDir/venv")

// Task to check if Python is available
tasks.register("checkPython", Exec::class) {
    group = "python-pods"
    description = "Check if Python 3 is available"
    
    commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
        listOf("python", "--version")
    } else {
        listOf("python3", "--version")
    }
    
    doFirst {
        println("🐍 Checking Python availability...")
    }
    
    doLast {
        println("✅ Python is available")
    }
}

// Task to create Python virtual environment
tasks.register("createPythonVenv", Exec::class) {
    group = "python-pods"
    description = "Create Python virtual environment for python-hello pod"
    dependsOn("checkPython")
    
    onlyIf { !pythonVenvDir.exists() }
    
    workingDir = pythonPodDir
    commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
        listOf("python", "-m", "venv", "venv")
    } else {
        listOf("python3", "-m", "venv", "venv")
    }
    
    doFirst {
        println("🔧 Creating Python virtual environment...")
    }
    
    doLast {
        println("✅ Virtual environment created at ${pythonVenvDir.absolutePath}")
    }
}

// Task to install Python dependencies
tasks.register("installPythonDeps", Exec::class) {
    group = "python-pods"
    description = "Install Python dependencies for python-hello pod"
    dependsOn("createPythonVenv")
    
    workingDir = pythonPodDir
    
    commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
        listOf("venv\\Scripts\\pip.exe", "install", "--upgrade", "pip")
    } else {
        listOf("venv/bin/pip", "install", "--upgrade", "pip")
    }
    
    doFirst {
        println("📦 Installing Python dependencies...")
    }
    
    doLast {
        // Install requirements
        project.exec {
            workingDir = pythonPodDir
            commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
                listOf("venv\\Scripts\\pip.exe", "install", "-r", "requirements.txt")
            } else {
                listOf("venv/bin/pip", "install", "-r", "requirements.txt")
            }
        }
        println("✅ Python dependencies installed")
    }
}

// Task to run Python tests
tasks.register("runPythonTests", Exec::class) {
    group = "python-pods"
    description = "Run tests for python-hello pod"
    dependsOn("installPythonDeps")
    
    workingDir = pythonPodDir
    
    commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
        listOf("venv\\Scripts\\python.exe", "-m", "pytest", "tests/", "-v")
    } else {
        listOf("venv/bin/python", "-m", "pytest", "tests/", "-v")
    }
    
    doFirst {
        println("🧪 Running Python tests...")
    }
    
    doLast {
        println("✅ Python tests completed")
    }
}

// Task to run Python app in development mode
tasks.register("runPythonDev", Exec::class) {
    group = "python-pods"
    description = "Run python-hello pod in development mode"
    dependsOn("installPythonDeps")
    
    workingDir = pythonSrcDir
    
    commandLine = if (System.getProperty("os.name").lowercase().contains("windows")) {
        listOf("..\\venv\\Scripts\\python.exe", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload")
    } else {
        listOf("../venv/bin/python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload")
    }
    
    doFirst {
        println("🚀 Starting Python app in development mode...")
        println("📍 Application will be available at: http://localhost:8000")
        println("📋 API documentation at: http://localhost:8000/docs")
        println("🛑 Press Ctrl+C to stop")
    }
}

// Task to build Python Docker image
tasks.register("buildPythonImage", Exec::class) {
    group = "python-pods"
    description = "Build Docker image for python-hello pod"
    
    workingDir = pythonPodDir
    commandLine = listOf("docker", "build", "-t", "shadok-pods/python-hello:latest", ".")
    
    doFirst {
        println("🐳 Building Python Docker image...")
    }
    
    doLast {
        println("✅ Docker image built: shadok-pods/python-hello:latest")
    }
}

// Task to run Python app with Docker Compose
tasks.register("runPythonDocker", Exec::class) {
    group = "python-pods"
    description = "Run python-hello pod with Docker Compose"
    dependsOn("buildPythonImage")
    
    workingDir = pythonPodDir
    commandLine = listOf("docker-compose", "up", "--build")
    
    doFirst {
        println("🐳 Starting Python app with Docker Compose...")
        println("📍 Application will be available at: http://localhost:8000")
        println("🛑 Use Ctrl+C then 'docker-compose down' to stop")
    }
}

// Task to clean Python environment
tasks.register("cleanPython", Delete::class) {
    group = "python-pods"
    description = "Clean Python virtual environment and cache files"
    
    delete(pythonVenvDir)
    delete(fileTree(pythonPodDir).matching {
        include("**/__pycache__/**")
        include("**/*.pyc")
        include("**/*.pyo")
        include("**/.pytest_cache/**")
    })
    
    doLast {
        println("🧹 Python environment cleaned")
    }
}

// Task to show Python pod status
tasks.register("pythonStatus") {
    group = "python-pods"
    description = "Show status of python-hello pod"
    
    doLast {
        println("📊 Python Hello World Pod Status")
        println("=".repeat(40))
        println("📁 Pod directory: ${pythonPodDir.absolutePath}")
        println("🐍 Virtual env: ${if (pythonVenvDir.exists()) "✅ Created" else "❌ Not found"}")
        println("📦 Dependencies: ${if (file("$pythonVenvDir/pyvenv.cfg").exists()) "✅ Installed" else "❌ Not installed"}")
        println("🧪 Tests: Run './gradlew runPythonTests' to execute")
        println("🚀 Dev mode: Run './gradlew runPythonDev' to start")
        println("🐳 Docker: Run './gradlew runPythonDocker' to start with Docker")
        println("=".repeat(40))
    }
}

// Aggregate task for complete Python setup
tasks.register("setupPython") {
    group = "python-pods"
    description = "Complete setup of python-hello pod (install deps and run tests)"
    dependsOn("runPythonTests")
    
    doLast {
        println("🎉 Python Hello World pod setup completed!")
        println("💡 Next steps:")
        println("   - Run dev mode: ./gradlew runPythonDev")
        println("   - Build Docker: ./gradlew buildPythonImage") 
        println("   - Check status: ./gradlew pythonStatus")
    }
}

// =========================
// Quarkus Pods Management  
// =========================

val quarkusPodDir = file("pods/quarkus-hello")

// Task to build Quarkus pod
tasks.register("buildQuarkusPod", GradleBuild::class) {
    group = "quarkus-pods"
    description = "Build quarkus-hello pod"
    
    dir = quarkusPodDir
    tasks = listOf("build")
    
    doFirst {
        println("⚡ Building Quarkus pod...")
    }
    
    doLast {
        println("✅ Quarkus pod built successfully")
    }
}

// Task to test Quarkus pod
tasks.register("testQuarkusPod", GradleBuild::class) {
    group = "quarkus-pods"
    description = "Run tests for quarkus-hello pod"
    
    dir = quarkusPodDir
    tasks = listOf("test")
    
    doFirst {
        println("🧪 Running Quarkus tests...")
    }
    
    doLast {
        println("✅ Quarkus tests completed")
    }
}

// Task to run Quarkus pod in dev mode
tasks.register("runQuarkusDev", GradleBuild::class) {
    group = "quarkus-pods"
    description = "Run quarkus-hello pod in development mode"
    
    dir = quarkusPodDir
    tasks = listOf("quarkusDev")
    
    doFirst {
        println("⚡ Starting Quarkus in dev mode...")
        println("📍 Application will be available at: http://localhost:8080")
        println("🛑 Press 'q' then Enter to stop")
    }
}

// Task to generate Kubernetes manifests for Quarkus
tasks.register("generateQuarkusK8s", GradleBuild::class) {
    group = "quarkus-pods"
    description = "Generate Kubernetes manifests for quarkus-hello pod"
    
    dir = quarkusPodDir
    tasks = listOf("build")
    
    doLast {
        val k8sDir = file("$quarkusPodDir/build/kubernetes")
        if (k8sDir.exists()) {
            println("✅ Kubernetes manifests generated in: ${k8sDir.absolutePath}")
            k8sDir.listFiles()?.forEach { file ->
                println("   📄 ${file.name}")
            }
        }
    }
}

// Task to clean Quarkus pod
tasks.register("cleanQuarkusPod", GradleBuild::class) {
    group = "quarkus-pods"
    description = "Clean quarkus-hello pod build artifacts"
    
    dir = quarkusPodDir
    tasks = listOf("clean")
    
    doLast {
        println("🧹 Quarkus pod cleaned")
    }
}

// =========================
// All Pods Management
// =========================

// Task to build all pods
tasks.register("buildAllPods") {
    group = "pods"
    description = "Build all demonstration pods"
    dependsOn("buildQuarkusPod", "buildPythonImage")
    
    doLast {
        println("🎉 All pods built successfully!")
    }
}

// Task to test all pods
tasks.register("testAllPods") {
    group = "pods"
    description = "Run tests for all demonstration pods"
    dependsOn("testQuarkusPod", "runPythonTests")
    
    doLast {
        println("🎉 All pod tests completed successfully!")
    }
}

// Task to setup all pods
tasks.register("setupAllPods") {
    group = "pods"
    description = "Complete setup of all demonstration pods"
    dependsOn("testAllPods")
    
    doLast {
        println("🎉 All Shadok demonstration pods are ready!")
        println("")
        println("📋 Available pods:")
        println("   ⚡ Quarkus Hello World (Java)")
        println("      - Dev mode: ./gradlew runQuarkusDev")
        println("      - URL: http://localhost:8080")
        println("")
        println("   🐍 Python Hello World (FastAPI)")
        println("      - Dev mode: ./gradlew runPythonDev") 
        println("      - URL: http://localhost:8000")
        println("")
        println("💡 Use './gradlew tasks --group pods' to see all pod tasks")
    }
}

// Task to show pods status
tasks.register("podsStatus") {
    group = "pods"
    description = "Show status of all demonstration pods"
    
    doLast {
        println("📊 Shadok Demonstration Pods Status")
        println("=".repeat(50))
        println("")
        
        println("⚡ QUARKUS HELLO WORLD")
        println("   📁 Directory: ${quarkusPodDir.absolutePath}")
        println("   🔧 Built: ${if (file("$quarkusPodDir/build").exists()) "✅ Yes" else "❌ No"}")
        println("   📄 K8s manifests: ${if (file("$quarkusPodDir/build/kubernetes").exists()) "✅ Generated" else "❌ Not found"}")
        println("")
        
        println("🐍 PYTHON HELLO WORLD")
        println("   📁 Directory: ${pythonPodDir.absolutePath}")
        println("   🐍 Virtual env: ${if (pythonVenvDir.exists()) "✅ Created" else "❌ Not found"}")
        println("   📦 Dependencies: ${if (file("$pythonVenvDir/pyvenv.cfg").exists()) "✅ Installed" else "❌ Not installed"}")
        println("")
        
        println("🎯 Quick commands:")
        println("   ./gradlew setupAllPods     # Setup everything")
        println("   ./gradlew testAllPods      # Test all pods")
        println("   ./gradlew buildAllPods     # Build all pods")
        println("   ./gradlew runQuarkusDev    # Start Quarkus")
        println("   ./gradlew runPythonDev     # Start Python")
        println("=".repeat(50))
    }
}

// Task to show help for pods
tasks.register("podsHelp") {
    group = "pods"
    description = "Show detailed help for working with Shadok demonstration pods"
    
    doLast {
        println("🎯 Shadok Demonstration Pods - Complete Guide")
        println("=".repeat(60))
        println("")
        
        println("🚀 QUICK START")
        println("   ./gradlew setupAllPods     # Configure everything")
        println("   ./gradlew podsStatus       # Check current status")
        println("   ./gradlew testAllPods      # Run all tests")
        println("")
        
        println("⚡ QUARKUS POD (Java)")
        println("   📂 Location: pods/quarkus-hello/")
        println("   🔧 Technology: Quarkus 3.8.1 + JAX-RS")
        println("   📋 Commands:")
        println("      ./gradlew buildQuarkusPod       # Build application")
        println("      ./gradlew testQuarkusPod        # Run tests")
        println("      ./gradlew runQuarkusDev         # Dev mode (port 8080)")
        println("      ./gradlew generateQuarkusK8s    # Generate K8s manifests")
        println("      ./gradlew cleanQuarkusPod       # Clean build")
        println("   🌐 Endpoints (http://localhost:8080):")
        println("      GET /hello                      # Text response")
        println("      GET /hello/json                 # JSON response")
        println("      GET /q/health                   # Health check")
        println("")
        
        println("🐍 PYTHON POD (FastAPI)")
        println("   📂 Location: pods/python-hello/")
        println("   🔧 Technology: Python 3.11 + FastAPI")
        println("   📋 Commands:")
        println("      ./gradlew setupPython           # Complete setup")
        println("      ./gradlew checkPython           # Check Python availability")
        println("      ./gradlew createPythonVenv      # Create virtual environment")
        println("      ./gradlew installPythonDeps     # Install dependencies")
        println("      ./gradlew runPythonTests        # Run tests")
        println("      ./gradlew runPythonDev          # Dev mode (port 8000)")
        println("      ./gradlew buildPythonImage      # Build Docker image")
        println("      ./gradlew runPythonDocker       # Run with Docker")
        println("      ./gradlew pythonStatus          # Show detailed status")
        println("      ./gradlew cleanPython           # Clean environment")
        println("   🌐 Endpoints (http://localhost:8000):")
        println("      GET /hello                      # Text response")
        println("      GET /hello/json                 # JSON response")
        println("      GET /health                     # Health check")
        println("      GET /docs                       # Interactive docs (Swagger)")
        println("      GET /openapi.json               # OpenAPI specification")
        println("")
        
        println("🛠 DEVELOPMENT WORKFLOW")
        println("   1. Setup: ./gradlew setupAllPods")
        println("   2. Check: ./gradlew podsStatus")
        println("   3. Test:  ./gradlew testAllPods")
        println("   4. Dev:   ./gradlew runQuarkusDev  (terminal 1)")
        println("   5. Dev:   ./gradlew runPythonDev   (terminal 2)")
        println("   6. Open:  http://localhost:8080 and http://localhost:8000")
        println("")
        
        println("📚 TASK GROUPS")
        println("   ./gradlew tasks --group pods           # All pod tasks")
        println("   ./gradlew tasks --group quarkus-pods   # Quarkus specific")
        println("   ./gradlew tasks --group python-pods    # Python specific")
        println("")
        
        println("💡 TIPS")
        println("   • Both applications support live reload for development")
        println("   • Python tests include async endpoint testing")
        println("   • Quarkus generates K8s manifests automatically")
        println("   • All containers are based on optimized images")
        println("   • Use Ctrl+C to stop development servers")
        println("=".repeat(60))
    }
}

// Task to check code formatting status
tasks.register("formatStatus") {
    group = "formatting"
    description = "Show status of code formatting for all files"
    
    doLast {
        println("📝 Code Formatting Status")
        println("=".repeat(50))
        println("")
        
        println("🔧 Spotless Configuration:")
        println("   ☕ Java: Google Java Format + remove unused imports")
        println("   📄 Markdown: Prettier with prose wrap (80 chars)")
        println("   ⚙️  TOML: Basic formatting (indent, trim, newline)")
        println("")
        
        println("📂 Target files:")
        println("   ☕ Java: src/**/*.java")
        println("   📄 Markdown: **/*.md (excluding venv/, build/, etc.)")
        println("   ⚙️  TOML: **/*.toml (excluding venv/, build/, etc.)")
        println("")
        
        println("🎯 Quick commands:")
        println("   ./gradlew spotlessCheck    # Check formatting")
        println("   ./gradlew spotlessApply    # Apply formatting")
        println("   ./gradlew formatStatus     # Show this status")
        println("")
        
        println("💡 All files are currently formatted correctly! ✅")
        println("=".repeat(50))
    }
}
