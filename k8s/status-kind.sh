#!/bin/bash

# Script pour vérifier le statut de l'environnement kind
# Usage: ./status-kind.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
REGISTRY_NAME="shadok-registry"
REGISTRY_PORT="5001"

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

# Vérifier le cluster kind
check_kind_cluster() {
    log_info "🎪 === Statut du cluster kind ==="
    
    if ! command -v kind &> /dev/null; then
        log_error "❌ kind n'est pas installé"
        return 1
    fi
    
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_success "✅ Cluster '${CLUSTER_NAME}' en cours d'exécution"
        
        # Afficher les informations du cluster
        echo ""
        log_info "📊 Informations du cluster:"
        kubectl cluster-info --context "kind-${CLUSTER_NAME}" 2>/dev/null || log_warning "⚠️  Impossible d'obtenir les infos du cluster"
        
        echo ""
        log_info "🖥️  Nodes du cluster:"
        kubectl get nodes --context "kind-${CLUSTER_NAME}" 2>/dev/null || log_warning "⚠️  Impossible d'obtenir les nodes"
        
        return 0
    else
        log_warning "❌ Cluster '${CLUSTER_NAME}' non trouvé"
        return 1
    fi
}

# Vérifier la registry locale
check_local_registry() {
    log_info "📦 === Statut de la registry locale ==="
    
    if docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        log_success "✅ Registry '${REGISTRY_NAME}' en cours d'exécution"
        
        # Vérifier la connectivité
        echo ""
        log_info "🌐 Test de connectivité:"
        if curl -s "http://localhost:${REGISTRY_PORT}/v2/" > /dev/null; then
            log_success "🚀 Registry accessible sur localhost:${REGISTRY_PORT}"
        else
            log_warning "⚠️  Registry non accessible sur localhost:${REGISTRY_PORT}"
        fi
        
        # Afficher les informations de la registry
        echo ""
        log_info "📋 Informations de la registry:"
        docker inspect "${REGISTRY_NAME}" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null | \
            grep -o '"IPAddress":"[^"]*"' | cut -d'"' -f4 | sed 's/^/  🌍 IP: /' || true
        
        return 0
    else
        log_warning "❌ Registry '${REGISTRY_NAME}' non trouvée"
        return 1
    fi
}

# Vérifier l'ingress controller
check_ingress_controller() {
    log_info "🌐 === Statut de l'ingress controller ==="
    
    if ! kubectl get namespace ingress-nginx --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_warning "⚠️  Namespace ingress-nginx non trouvé"
        return 1
    fi
    
    # Vérifier les pods ingress
    local ready_pods=$(kubectl get pods -n ingress-nginx --context "kind-${CLUSTER_NAME}" \
        --selector=app.kubernetes.io/component=controller \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ready_pods" -gt 0 ]; then
        log_success "✅ Ingress controller en cours d'exécution ($ready_pods pod(s))"
        
        echo ""
        log_info "🏃 Pods ingress-nginx:"
        kubectl get pods -n ingress-nginx --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
        
        return 0
    else
        log_warning "❌ Ingress controller non prêt"
        return 1
    fi
}

# Vérifier la connectivité réseau
check_network_connectivity() {
    log_info "🔗 === Connectivité réseau ==="
    
    # Vérifier si la registry est connectée au réseau kind
    if docker network inspect kind &> /dev/null; then
        local registry_connected=$(docker network inspect kind --format '{{range .Containers}}{{.Name}} {{end}}' | grep -o "${REGISTRY_NAME}" || echo "")
        
        if [ -n "$registry_connected" ]; then
            log_success "✅ Registry connectée au réseau kind"
        else
            log_warning "⚠️  Registry non connectée au réseau kind"
        fi
    else
        log_warning "⚠️  Réseau kind non trouvé"
    fi
    
    # Vérifier les ports exposés
    echo ""
    log_info "🚪 Ports exposés:"
    if netstat -an | grep -q ":80.*LISTEN"; then
        log_success "✅ Port 80 (HTTP) exposé"
    else
        log_warning "⚠️  Port 80 (HTTP) non exposé"
    fi
    
    if netstat -an | grep -q ":443.*LISTEN"; then
        log_success "✅ Port 443 (HTTPS) exposé"
    else
        log_warning "⚠️  Port 443 (HTTPS) non exposé"
    fi
    
    if netstat -an | grep -q ":${REGISTRY_PORT}.*LISTEN"; then
        log_success "✅ Port ${REGISTRY_PORT} (Registry) exposé"
    else
        log_warning "⚠️  Port ${REGISTRY_PORT} (Registry) non exposé"
    fi
}

# Afficher les commandes utiles
show_useful_commands() {
    log_info "🛠️  === Commandes utiles ==="
    echo ""
    echo "# 🎪 Gérer le cluster:"
    echo "  kubectl --context kind-${CLUSTER_NAME} get nodes"
    echo "  kubectl --context kind-${CLUSTER_NAME} get pods -A"
    echo ""
    echo "# 📦 Tester la registry:"
    echo "  curl http://localhost:${REGISTRY_PORT}/v2/"
    echo "  docker tag hello-world localhost:${REGISTRY_PORT}/hello-world"
    echo "  docker push localhost:${REGISTRY_PORT}/hello-world"
    echo ""
    echo "# 🔍 Logs et debug:"
    echo "  docker logs ${REGISTRY_NAME}"
    echo "  kubectl --context kind-${CLUSTER_NAME} logs -n ingress-nginx -l app.kubernetes.io/component=controller"
    echo ""
    echo "# 🛑 Arrêter l'environnement:"
    echo "  ./stop-kind.sh ${CLUSTER_NAME}"
}

# Fonction principale
main() {
    log_info "🔍 === Vérification de l'environnement kind '${CLUSTER_NAME}' ==="
    echo ""
    
    local cluster_ok=0
    local registry_ok=0
    local ingress_ok=0
    
    # Vérifications
    check_kind_cluster && cluster_ok=1
    echo ""
    check_local_registry && registry_ok=1
    echo ""
    
    if [ "$cluster_ok" -eq 1 ]; then
        check_ingress_controller && ingress_ok=1
        echo ""
        check_network_connectivity
        echo ""
    fi
    
    # Résumé
    log_info "📊 === Résumé ==="
    [ "$cluster_ok" -eq 1 ] && log_success "✅ Cluster kind" || log_error "❌ Cluster kind"
    [ "$registry_ok" -eq 1 ] && log_success "✅ Registry locale" || log_error "❌ Registry locale"
    [ "$ingress_ok" -eq 1 ] && log_success "✅ Ingress controller" || log_error "❌ Ingress controller"
    
    echo ""
    if [ "$cluster_ok" -eq 1 ] && [ "$registry_ok" -eq 1 ] && [ "$ingress_ok" -eq 1 ]; then
        log_success "🎉 Environnement complètement opérationnel !"
    elif [ "$cluster_ok" -eq 1 ] || [ "$registry_ok" -eq 1 ]; then
        log_warning "⚠️  Environnement partiellement opérationnel"
        echo "   🔧 Utilisez ./start-kind.sh pour recréer l'environnement complet"
    else
        log_error "💥 Environnement non opérationnel"
        echo "   🚀 Utilisez ./start-kind.sh pour créer l'environnement"
    fi
    
    echo ""
    show_useful_commands
}

# Exécuter le script principal
main "$@"
