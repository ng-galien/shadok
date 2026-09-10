#!/bin/bash

# Startup script for the Python Hello World application

set -e

echo "🐍 Starting the Python Hello World application"

# Help function
show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  dev       Start development mode with live reload"
    echo "  install   Install Python dependencies"
    echo "  build     Build the Docker image"
    echo "  test      Run pytest tests"
    echo "  docker    Build and run with Docker Compose"
    echo "  k8s       Apply Kubernetes manifests"
    echo "  clean     Clean temporary files"
    echo "  help      Show this help"
    echo ""
}

# Check Python availability
check_python() {
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 is not installed"
        exit 1
    fi
    echo "✅ Python $(python3 --version) detected"
}

# Installing dependencies
install_deps() {
    echo "📦 Installing Python dependencies..."

    # Create a virtual environment when needed
    if [ ! -d "venv" ]; then
        echo "🔧 Creating the virtual environment..."
        python3 -m venv venv
    fi

    # Activate the virtual environment
    source venv/bin/activate

    # Installing dependencies
    pip install --upgrade pip
    pip install -r requirements.txt

    echo "✅ Dependencies installed!"
}

# Check arguments
case "${1:-help}" in
    "dev")
        echo "🔄 Starting development mode..."
        check_python
        install_deps
        source venv/bin/activate
        cd src
        python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
        ;;
    "install")
        echo "📦 Installing dependencies..."
        check_python
        install_deps
        ;;
    "build")
        echo "🔨 Building the Docker image..."
        docker build -t shadok-pods/python-hello:latest .
        echo "✅ Image built: shadok-pods/python-hello:latest"
        ;;
    "test")
        echo "🧪 Running tests..."
        check_python
        install_deps
        source venv/bin/activate
        python -m pytest tests/ -v
        echo "✅ Tests completed!"
        ;;
    "docker")
        echo "🐳 Building and starting with Docker..."
        docker-compose up --build
        ;;
    "k8s")
        echo "☸️  Applying Kubernetes manifests..."
        kubectl apply -f k8s/
        echo "✅ Manifests applied!"
        echo "📋 To check the deployment:"
        echo "   kubectl get pods -l app.kubernetes.io/name=python-hello"
        echo "   kubectl get svc python-hello"
        ;;
    "clean")
        echo "🧹 Cleaning..."
        rm -rf venv/
        rm -rf __pycache__/
        rm -rf .pytest_cache/
        find . -name "*.pyc" -delete
        find . -name "*.pyo" -delete
        echo "✅ Cleanup completed!"
        ;;
    "help")
        show_help
        ;;
    *)
        echo "❌ Invalid option: $1"
        show_help
        exit 1
        ;;
esac
