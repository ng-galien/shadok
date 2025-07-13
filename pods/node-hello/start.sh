#!/bin/bash

# Script de démarrage pour l'application Node.js Hello World

set -e

echo "🚀 Démarrage de l'application Node.js Hello World"

# Fonction d'aide
show_help() {
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  dev, development    Démarrer en mode développement avec live reload"
  echo "  prod, production    Démarrer en mode production"
  echo "  test                Exécuter les tests"
  echo "  install             Installer les dépendances"
  echo "  help, -h, --help    Afficher cette aide"
  echo ""
  echo "Variables d'environnement:"
  echo "  PORT                Port d'écoute (défaut: 3000)"
  echo "  HOST                Adresse d'écoute (défaut: 0.0.0.0)"
  echo "  NODE_ENV            Environnement (development/production)"
  echo ""
  echo "Exemples:"
  echo "  $0 dev              # Mode développement avec nodemon"
  echo "  $0 prod             # Mode production"
  echo "  PORT=8080 $0 dev    # Mode dev sur le port 8080"
  echo ""
}

# Vérification de Node.js
check_node() {
  if ! command -v node &> /dev/null; then
    echo "❌ Node.js n'est pas installé"
    echo "📥 Veuillez installer Node.js 18+ depuis https://nodejs.org/"
    exit 1
  fi

  echo "✅ Node.js version: $(node --version)"
}

# Installation des dépendances
install_deps() {
  echo "📦 Installation des dépendances..."
  if [ -f "package-lock.json" ]; then
    npm ci
  else
    npm install
  fi
  echo "✅ Dépendances installées"
}

# Vérification des dépendances
check_deps() {
  if [ ! -d "node_modules" ]; then
    echo "📦 Installation des dépendances nécessaire..."
    install_deps
  fi
}

# Mode développement
start_dev() {
  echo "🔧 Mode développement avec live reload"
  export NODE_ENV=development
  export PORT=${PORT:-3000}
  export HOST=${HOST:-0.0.0.0}

  check_deps

  echo "🌐 Serveur disponible sur http://localhost:${PORT}"
  echo "🔄 Live reload activé avec nodemon"
  echo "📊 Endpoints disponibles:"
  echo "   GET /          - Informations du service"
  echo "   GET /hello     - Salutation simple"
  echo "   GET /hello/json - Réponse JSON détaillée"
  echo "   GET /health    - Vérification de santé"
  echo "   GET /ready     - Vérification de disponibilité"
  echo ""
  echo "💡 Appuyez sur Ctrl+C pour arrêter"
  echo ""

  npm run dev
}

# Mode production
start_prod() {
  echo "🚀 Mode production"
  export NODE_ENV=production
  export PORT=${PORT:-3000}
  export HOST=${HOST:-0.0.0.0}

  check_deps

  echo "🌐 Serveur disponible sur http://localhost:${PORT}"
  echo "📊 Endpoints disponibles:"
  echo "   GET /          - Informations du service"
  echo "   GET /hello     - Salutation simple"
  echo "   GET /hello/json - Réponse JSON détaillée"
  echo "   GET /health    - Vérification de santé"
  echo "   GET /ready     - Vérification de disponibilité"
  echo ""

  npm start
}

# Exécution des tests
run_tests() {
  echo "🧪 Exécution des tests"
  check_deps
  npm test
}

# Traitement des arguments
case "${1:-dev}" in
  "dev"|"development")
    check_node
    start_dev
    ;;
  "prod"|"production")
    check_node
    start_prod
    ;;
  "test")
    check_node
    run_tests
    ;;
  "install")
    check_node
    install_deps
    ;;
  "help"|"-h"|"--help")
    show_help
    ;;
  *)
    echo "❌ Option inconnue: $1"
    show_help
    exit 1
    ;;
esac
