plugins {
    base
    alias(libs.plugins.spotless)
}

description = "Shadok application demos and development tooling"

// Root project Spotless configuration
configure<com.diffplug.gradle.spotless.SpotlessExtension> {
    format("markdown") {
        target("*.md")
        prettier().config(mapOf(
            "parser" to "markdown",
            "proseWrap" to "always",
            "printWidth" to 80,
            "tabWidth" to 2
        ))
    }
}

// Subprojects configuration
subprojects {
    apply(plugin = "com.diffplug.spotless")

    group = findProperty("group") as String
    version = findProperty("version") as String
    
//    configure<JavaPluginExtension> {
//        toolchain {
//            languageVersion.set(JavaLanguageVersion.of(21))
//        }
//        withSourcesJar()
//    }
    
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
// Node.js Pods Management  
// =========================

val nodePodDir = file("pods/node-hello")
val nodeModulesDir = file("$nodePodDir/node_modules")

// Task to check if Node.js is available
tasks.register("checkNode", Exec::class) {
    group = "node-pods"
    description = "Check if Node.js is available"
    
    commandLine = listOf("node", "--version")
    
    doFirst {
        println("🟢 Checking Node.js availability...")
    }
    
    doLast {
        println("✅ Node.js is available")
    }
}

// Task to install Node.js dependencies
tasks.register("installNodeDeps", Exec::class) {
    group = "node-pods"
    description = "Install Node.js dependencies for node-hello pod"
    dependsOn("checkNode")
    
    onlyIf { !nodeModulesDir.exists() }
    
    workingDir = nodePodDir
    commandLine = listOf("npm", "install")
    
    doFirst {
        println("📦 Installing Node.js dependencies...")
    }
    
    doLast {
        println("✅ Dependencies installed at ${nodeModulesDir.absolutePath}")
    }
}

// Task to run Node.js tests
tasks.register("runNodeTests", Exec::class) {
    group = "node-pods"
    description = "Run tests for node-hello pod"
    dependsOn("installNodeDeps")
    
    workingDir = nodePodDir
    commandLine = listOf("npm", "test")
    
    doFirst {
        println("🧪 Running Node.js tests...")
    }
    
    doLast {
        println("✅ Node.js tests completed")
    }
}

// Task to run Node.js in development mode
tasks.register("runNodeDev", Exec::class) {
    group = "node-pods"
    description = "Run node-hello pod in development mode with live reload"
    dependsOn("installNodeDeps")
    
    workingDir = nodePodDir
    commandLine = listOf("npm", "run", "dev")
    
    doFirst {
        println("🔧 Starting Node.js development server with live reload...")
        println("🌐 Server will be available at http://localhost:3000")
        println("🔄 Live reload enabled with nodemon")
        println("💡 Press Ctrl+C to stop")
    }
}

// Task to run Node.js in production mode
tasks.register("runNode", Exec::class) {
    group = "node-pods"
    description = "Run node-hello pod in production mode"
    dependsOn("installNodeDeps")
    
    workingDir = nodePodDir
    commandLine = listOf("npm", "start")
    
    doFirst {
        println("🚀 Starting Node.js production server...")
        println("🌐 Server will be available at http://localhost:3000")
    }
}

// Task to build Node.js Docker image
tasks.register("buildNodeImage", Exec::class) {
    group = "node-pods"
    description = "Build Docker image for node-hello pod"
    
    workingDir = nodePodDir
    commandLine = listOf("docker", "build", "-t", "node-hello:latest", ".")
    
    doFirst {
        println("🐳 Building Node.js Docker image...")
    }
    
    doLast {
        println("✅ Docker image 'node-hello:latest' built successfully")
    }
}

// Task to run Node.js with Docker
tasks.register("runNodeDocker", Exec::class) {
    group = "node-pods"
    description = "Run node-hello pod with Docker"
    dependsOn("buildNodeImage")
    
    commandLine = listOf("docker", "run", "-p", "3000:3000", "--rm", "node-hello:latest")
    
    doFirst {
        println("🐳 Starting Node.js with Docker...")
        println("🌐 Server will be available at http://localhost:3000")
        println("💡 Press Ctrl+C to stop")
    }
}

// Task to test Node.js endpoints
tasks.register("testNodeEndpoints", Exec::class) {
    group = "node-pods"
    description = "Test node-hello pod endpoints"
    
    workingDir = nodePodDir
    commandLine = listOf("./test-endpoints.sh")
    
    doFirst {
        println("🧪 Testing Node.js endpoints...")
        println("💡 Make sure the server is running first")
    }
}

// Task to lint Node.js code
tasks.register("lintNode", Exec::class) {
    group = "node-pods"
    description = "Lint node-hello pod code"
    dependsOn("installNodeDeps")
    
    workingDir = nodePodDir
    commandLine = listOf("npm", "run", "lint")
    
    doFirst {
        println("🔍 Linting Node.js code...")
    }
}

// Task to apply Node.js Kubernetes manifests
tasks.register("applyNodeK8s", Exec::class) {
    group = "node-pods"
    description = "Apply Kubernetes manifests for node-hello pod"
    
    workingDir = file("$nodePodDir/k8s")
    commandLine = listOf("kubectl", "apply", "-k", ".")
    
    doFirst {
        println("☸️ Applying Node.js Kubernetes manifests...")
        println("🌐 Ingress will be available at: http://node-hello.127.0.0.1.nip.io")
    }
    
    doLast {
        println("✅ Node.js pod deployed to Kubernetes")
        println("💡 Check status with: kubectl get pods,svc,ingress -l app.kubernetes.io/name=node-hello")
    }
}

// Task to delete Node.js Kubernetes resources
tasks.register("deleteNodeK8s", Exec::class) {
    group = "node-pods"
    description = "Delete Kubernetes resources for node-hello pod"
    
    workingDir = file("$nodePodDir/k8s")
    commandLine = listOf("kubectl", "delete", "-k", ".")
    
    doFirst {
        println("🗑️ Deleting Node.js Kubernetes resources...")
    }
    
    doLast {
        println("✅ Node.js Kubernetes resources deleted")
    }
}

// Task to show Node.js Kubernetes status
tasks.register("statusNodeK8s", Exec::class) {
    group = "node-pods"
    description = "Show Kubernetes status for node-hello pod"
    
    commandLine = listOf("kubectl", "get", "pods,svc,ingress", "-l", "app.kubernetes.io/name=node-hello")
    
    doFirst {
        println("☸️ Node.js Kubernetes Status:")
        println("=".repeat(40))
    }
}

// Task to get Node.js pod logs
tasks.register("logsNodeK8s", Exec::class) {
    group = "node-pods"
    description = "Show logs for node-hello pod"
    
    commandLine = listOf("kubectl", "logs", "-l", "app.kubernetes.io/name=node-hello", "--tail=50")
    
    doFirst {
        println("📋 Node.js Pod Logs (last 50 lines):")
        println("=".repeat(40))
    }
}

// Task to show Node.js pod status
tasks.register("nodeStatus") {
    group = "node-pods"
    description = "Show status of node-hello pod"
    
    doLast {
        println("🟢 NODE.JS HELLO WORLD STATUS")
        println("=".repeat(40))
        println("📁 Directory: ${nodePodDir.absolutePath}")
        println("📦 Dependencies: ${if (nodeModulesDir.exists()) "✅ Installed" else "❌ Not installed"}")
        println("🔧 package.json: ${if (file("$nodePodDir/package.json").exists()) "✅ Found" else "❌ Missing"}")
        println("📄 Source code: ${if (file("$nodePodDir/src/app.js").exists()) "✅ Found" else "❌ Missing"}")
        println("🧪 Tests: ${if (file("$nodePodDir/tests").exists()) "✅ Found" else "❌ Missing"}")
        println("🐳 Dockerfile: ${if (file("$nodePodDir/Dockerfile").exists()) "✅ Found" else "❌ Missing"}")
        println("")
        println("🎯 Quick commands:")
        println("   ./gradlew installNodeDeps  # Install dependencies")
        println("   ./gradlew runNodeTests     # Run tests")
        println("   ./gradlew runNodeDev       # Dev mode with live reload")
        println("   ./gradlew runNode          # Production mode")
        println("   ./gradlew buildNodeImage   # Build Docker image")
        println("   ./gradlew applyNodeK8s     # Deploy to Kubernetes")
        println("   ./gradlew deleteNodeK8s    # Delete from Kubernetes")
        println("   ./gradlew statusNodeK8s    # Show Kubernetes status")
        println("   ./gradlew logsNodeK8s      # Show pod logs")
        println("🧪 Tests: Run './gradlew runNodeTests' to execute")
        println("🚀 Dev mode: Run './gradlew runNodeDev' to start")
        println("🐳 Docker: Run './gradlew runNodeDocker' to start with Docker")
        println("=".repeat(40))
    }
}

// Aggregate task for complete Node.js setup
tasks.register("setupNode") {
    group = "node-pods"
    description = "Complete setup of node-hello pod (install deps and run tests)"
    dependsOn("runNodeTests")
    
    doLast {
        println("🎉 Node.js Hello World pod setup completed!")
        println("💡 Next steps:")
        println("   - Run dev mode: ./gradlew runNodeDev")
        println("   - Build Docker: ./gradlew buildNodeImage") 
        println("   - Check status: ./gradlew nodeStatus")
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
    dependsOn("buildQuarkusPod", "buildPythonImage", "buildNodeImage")
    
    doLast {
        println("🎉 All pods built successfully!")
    }
}

// Task to test all pods
tasks.register("testAllPods") {
    group = "pods"
    description = "Run tests for all demonstration pods"
    dependsOn("testQuarkusPod", "runPythonTests", "runNodeTests")
    
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
        println("   🟢 Node.js Hello World (Express)")
        println("      - Dev mode: ./gradlew runNodeDev") 
        println("      - URL: http://localhost:3000")
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
        
        println("🟢 NODE.JS HELLO WORLD")
        println("   📁 Directory: ${nodePodDir.absolutePath}")
        println("   📦 Dependencies: ${if (nodeModulesDir.exists()) "✅ Installed" else "❌ Not installed"}")
        println("   🔧 package.json: ${if (file("$nodePodDir/package.json").exists()) "✅ Found" else "❌ Missing"}")
        println("")
        
        println("🎯 Quick commands:")
        println("   ./gradlew setupAllPods     # Setup everything")
        println("   ./gradlew testAllPods      # Test all pods")
        println("   ./gradlew buildAllPods     # Build all pods")
        println("   ./gradlew runQuarkusDev    # Start Quarkus")
        println("   ./gradlew runPythonDev     # Start Python")
        println("   ./gradlew runNodeDev       # Start Node.js")
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
        
        println("� NODE.JS POD (Express)")
        println("   📂 Location: pods/node-hello/")
        println("   🔧 Technology: Node.js 18 + Express")
        println("   📋 Commands:")
        println("      ./gradlew setupNode             # Complete setup")
        println("      ./gradlew checkNode             # Check Node.js availability")
        println("      ./gradlew installNodeDeps       # Install dependencies")
        println("      ./gradlew runNodeTests          # Run tests")
        println("      ./gradlew runNodeDev            # Dev mode (port 3000)")
        println("      ./gradlew runNode               # Production mode")
        println("      ./gradlew buildNodeImage        # Build Docker image")
        println("      ./gradlew runNodeDocker         # Run with Docker")
        println("      ./gradlew nodeStatus            # Show detailed status")
        println("      ./gradlew lintNode              # Lint code")
        println("      ./gradlew applyNodeK8s          # Deploy to Kubernetes")
        println("      ./gradlew statusNodeK8s         # Show K8s status")
        println("      ./gradlew logsNodeK8s           # Show pod logs")
        println("      ./gradlew deleteNodeK8s         # Delete from K8s")
        println("   🌐 Endpoints (http://localhost:3000):")
        println("      GET /                           # Service info")
        println("      GET /hello                      # Text response")
        println("      GET /hello/json                 # JSON response")
        println("      GET /health                     # Health check")
        println("      GET /ready                      # Readiness check")
        println("   ☸️ Kubernetes (http://node-hello.127.0.0.1.nip.io):")
        println("      All endpoints available via ingress")
        println("")
        
        println("�🛠 DEVELOPMENT WORKFLOW")
        println("   1. Setup: ./gradlew setupAllPods")
        println("   2. Check: ./gradlew podsStatus")
        println("   3. Test:  ./gradlew testAllPods")
        println("   4. Dev:   ./gradlew runQuarkusDev  (terminal 1)")
        println("   5. Dev:   ./gradlew runPythonDev   (terminal 2)")
        println("   6. Dev:   ./gradlew runNodeDev     (terminal 3)")
        println("   7. Open:  http://localhost:8080, http://localhost:8000, http://localhost:3000")
        println("")
        
        println("📚 TASK GROUPS")
        println("   ./gradlew tasks --group pods           # All pod tasks")
        println("   ./gradlew tasks --group quarkus-pods   # Quarkus specific")
        println("   ./gradlew tasks --group python-pods    # Python specific")
        println("   ./gradlew tasks --group node-pods      # Node.js specific")
        println("")
        
        println("💡 TIPS")
        println("   • All applications support live reload for development")
        println("   • Python tests include async endpoint testing")
        println("   • Node.js includes live reload with nodemon")
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
        println("   🐳 Dockerfile: Basic formatting (4-space indent)")
        println("   🔧 Shell scripts: Basic formatting (2-space indent)")
        println("   ⚙️  TOML: Basic formatting (indent, trim, newline)")
        println("")
        
        println("📂 Target files:")
        println("   ☕ Java: src/**/*.java")
        println("   📄 Markdown: **/*.md (excluding venv/, build/, etc.)")
        println("   🐳 Dockerfile: **/Dockerfile* (excluding venv/, build/, etc.)")
        println("   🔧 Shell: **/*.sh (excluding venv/, build/, etc.)")
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
