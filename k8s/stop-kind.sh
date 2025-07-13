#!/bin/bash

# Script pour arrêter et nettoyer l'environnement kind
# Usage: ./stop-kind.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
REGISTRY_NAME="shadok-registry"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Arrêter le cluster kind
stop_kind_cluster() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_info "🛑 Arrêt du cluster kind '${CLUSTER_NAME}'..."
        kind delete cluster --name "${CLUSTER_NAME}"
        log_success "✅ Cluster kind '${CLUSTER_NAME}' supprimé"
    else
        log_warning "⚠️  Cluster kind '${CLUSTER_NAME}' non trouvé"
    fi
}

# Arrêter la registry locale
stop_local_registry() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        log_info "📦 Arrêt de la registry locale '${REGISTRY_NAME}'..."
        docker rm -f "${REGISTRY_NAME}"
        log_success "✅ Registry locale '${REGISTRY_NAME}' supprimée"
    else
        log_warning "⚠️  Registry locale '${REGISTRY_NAME}' non trouvée"
    fi
}

# Nettoyer les réseaux Docker orphelins
cleanup_docker_networks() {
    log_info "🧹 Nettoyage des réseaux Docker orphelins..."
    docker network prune -f
    log_success "✨ Réseaux Docker nettoyés"
}

# Afficher le statut final
show_status() {
    log_success "🎯 === Nettoyage terminé ==="
    echo ""
    log_info "📋 État final:"
    
    # Vérifier les clusters kind restants
    if kind get clusters &> /dev/null; then
        echo "  - 🎪 Clusters kind restants:"
        kind get clusters | sed 's/^/    • /'
    else
        echo "  - 🚫 Aucun cluster kind en cours d'exécution"
    fi
    
    # Vérifier les registries restantes
    if docker ps --format '{{.Names}}' | grep -q registry; then
        echo "  - 📦 Registries Docker restantes:"
        docker ps --format '{{.Names}}' | grep registry | sed 's/^/    • /'
    else
        echo "  - 🚫 Aucune registry Docker en cours d'exécution"
    fi
    
    echo ""
}

# Fonction principale
main() {
    log_info "🛑 === Arrêt de l'environnement kind ==="
    echo ""
    
    stop_kind_cluster
    stop_local_registry
    cleanup_docker_networks
    
    show_status
}

# Exécuter le script principal
main "$@"
