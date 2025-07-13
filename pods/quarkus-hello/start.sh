#!/bin/bash

# Script de démarrage pour l'application Quarkus Hello World

set -e

echo "🚀 Démarrage de l'application Quarkus Hello World"

# Fonction d'aide
show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  dev       Démarre en mode développement avec live reload"
    echo "  build     Construit l'application"
    echo "  test      Lance les tests"
    echo "  docker    Construit et lance avec Docker Compose"
    echo "  k8s       Génère les manifests Kubernetes"
    echo "  clean     Nettoie les fichiers de build"
    echo "  help      Affiche cette aide"
    echo ""
}

# Vérification des arguments
case "${1:-help}" in
    "dev")
        echo "🔄 Démarrage en mode développement..."
        ./gradlew quarkusDev
        ;;
    "build")
        echo "🔨 Construction de l'application..."
        ./gradlew build
        echo "✅ Build terminé!"
        ;;
    "test")
        echo "🧪 Lancement des tests..."
        ./gradlew test
        echo "✅ Tests terminés!"
        ;;
    "docker")
        echo "🐳 Construction et démarrage avec Docker..."
        ./gradlew build
        docker-compose up --build
        ;;
    "k8s")
        echo "☸️  Génération des manifests Kubernetes..."
        ./gradlew build
        echo "📁 Manifests générés dans build/kubernetes/"
        ls -la build/kubernetes/ || echo "❌ Aucun manifest trouvé"
        ;;
    "clean")
        echo "🧹 Nettoyage..."
        ./gradlew clean
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
