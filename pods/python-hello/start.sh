#!/bin/bash

# Script de démarrage pour l'application Python Hello World

set -e

echo "🐍 Démarrage de l'application Python Hello World"

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  dev       Démarre en mode développement avec live reload"
    echo "  install   Installe les dépendances Python"
    echo "  build     Construit l'image Docker"
    echo "  test      Lance les tests avec pytest"
    echo "  docker    Construit et lance avec Docker Compose"
    echo "  k8s       Applique les manifests Kubernetes"
    echo "  clean     Nettoie les fichiers temporaires"
    echo "  help      Affiche cette aide"
    echo ""
}

# Vérification de Python
check_python() {
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 n'est pas installé"
        exit 1
    fi
    echo "✅ Python $(python3 --version) détecté"
}

# Installation des dépendances
install_deps() {
    echo "📦 Installation des dépendances Python..."

    # Création de l'environnement virtuel si nécessaire
    if [ ! -d "venv" ]; then
        echo "🔧 Création de l'environnement virtuel..."
        python3 -m venv venv
    fi

    # Activation de l'environnement virtuel
    source venv/bin/activate

    # Installation des dépendances
    pip install --upgrade pip
    pip install -r requirements.txt

    echo "✅ Dépendances installées!"
}

# Vérification des arguments
case "${1:-help}" in
    "dev")
        echo "🔄 Démarrage en mode développement..."
        check_python
        install_deps
        source venv/bin/activate
        cd src
        python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
        ;;
    "install")
        echo "📦 Installation des dépendances..."
        check_python
        install_deps
        ;;
    "build")
        echo "🔨 Construction de l'image Docker..."
        docker build -t shadok-pods/python-hello:latest .
        echo "✅ Image construite: shadok-pods/python-hello:latest"
        ;;
    "test")
        echo "🧪 Lancement des tests..."
        check_python
        install_deps
        source venv/bin/activate
        python -m pytest tests/ -v
        echo "✅ Tests terminés!"
        ;;
    "docker")
        echo "🐳 Construction et démarrage avec Docker..."
        docker-compose up --build
        ;;
    "k8s")
        echo "☸️  Application des manifests Kubernetes..."
        kubectl apply -f k8s/
        echo "✅ Manifests appliqués!"
        echo "📋 Pour vérifier le déploiement:"
        echo "   kubectl get pods -l app.kubernetes.io/name=python-hello"
        echo "   kubectl get svc python-hello"
        ;;
    "clean")
        echo "🧹 Nettoyage..."
        rm -rf venv/
        rm -rf __pycache__/
        rm -rf .pytest_cache/
        find . -name "*.pyc" -delete
        find . -name "*.pyo" -delete
        echo "✅ Nettoyage terminé!"
        ;;
    "help")
        show_help
        ;;
    *)
        echo "❌ Option invalide: $1"
        show_help
        exit 1
        ;;
esac
