#!/bin/bash

# Script de test pour l'environnement kind
# Usage: ./test-kind.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
REGISTRY_NAME="shadok-registry"
REGISTRY_PORT="5001"
TEST_IMAGE="hello-world"
TEST_TAG="localhost:${REGISTRY_PORT}/test/${TEST_IMAGE}:latest"

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

# Test de la registry locale
test_local_registry() {
    log_info "📦 === Test de la registry locale ==="
    
    # Vérifier la connectivité
    if ! curl -s "http://localhost:${REGISTRY_PORT}/v2/" > /dev/null; then
        log_error "❌ Registry non accessible sur localhost:${REGISTRY_PORT}"
        return 1
    fi
    log_success "✅ Registry accessible"
    
    # Test push/pull d'une image
    log_info "🚀 Test push/pull d'une image..."
    
    # Pull de l'image de test
    docker pull ${TEST_IMAGE} > /dev/null 2>&1
    
    # Tag pour la registry locale
    docker tag ${TEST_IMAGE} ${TEST_TAG}
    
    # Push vers la registry locale
    if docker push ${TEST_TAG} > /dev/null 2>&1; then
        log_success "⬆️  Push vers la registry locale réussi"
    else
        log_error "❌ Échec du push vers la registry locale"
        return 1
    fi
    
    # Supprimer l'image locale et la re-pull depuis la registry
    docker rmi ${TEST_TAG} > /dev/null 2>&1 || true
    
    if docker pull ${TEST_TAG} > /dev/null 2>&1; then
        log_success "⬇️  Pull depuis la registry locale réussi"
    else
        log_error "❌ Échec du pull depuis la registry locale"
        return 1
    fi
    
    # Nettoyer
    docker rmi ${TEST_TAG} > /dev/null 2>&1 || true
    
    return 0
}

# Test du cluster Kubernetes
test_kubernetes_cluster() {
    log_info "🎪 === Test du cluster Kubernetes ==="
    
    # Vérifier la connectivité kubectl
    if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1; then
        log_error "❌ Impossible de se connecter au cluster"
        return 1
    fi
    log_success "✅ Connexion au cluster réussie"
    
    # Vérifier que tous les nodes sont prêts
    local ready_nodes=$(kubectl get nodes --context "kind-${CLUSTER_NAME}" --no-headers 2>/dev/null | \
        awk '$2=="Ready" {count++} END {print count+0}')
    
    if [ "$ready_nodes" -ge 3 ]; then
        log_success "🖥️  Tous les nodes sont prêts ($ready_nodes/3)"
    else
        log_warning "⚠️  Certains nodes ne sont pas prêts ($ready_nodes/3)"
    fi
    
    # Test de déploiement d'un pod simple
    log_info "🚀 Test de déploiement d'un pod..."
    
    local test_pod_yaml="/tmp/test-pod-${CLUSTER_NAME}.yaml"
    cat > "$test_pod_yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-registry-pod
  namespace: default
spec:
  containers:
  - name: test
    image: ${TEST_TAG}
    command: ['echo', 'Test réussi depuis la registry locale']
  restartPolicy: Never
EOF
    
    # Déployer le pod
    if kubectl apply -f "$test_pod_yaml" --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1; then
        log_success "✅ Pod de test déployé"
        
        # Attendre que le pod soit terminé
        kubectl wait --for=condition=Ready pod/test-registry-pod \
            --context "kind-${CLUSTER_NAME}" --timeout=60s > /dev/null 2>&1 || true
        
        # Nettoyer
        kubectl delete -f "$test_pod_yaml" --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1 || true
        rm -f "$test_pod_yaml"
        
        log_success "🧹 Pod de test nettoyé"
    else
        log_error "❌ Échec du déploiement du pod de test"
        rm -f "$test_pod_yaml"
        return 1
    fi
    
    return 0
}

# Test de l'ingress controller
test_ingress_controller() {
    log_info "🌐 === Test de l'ingress controller ==="
    
    # Vérifier que les pods ingress sont prêts
    local ready_ingress=$(kubectl get pods -n ingress-nginx --context "kind-${CLUSTER_NAME}" \
        --selector=app.kubernetes.io/component=controller \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ready_ingress" -gt 0 ]; then
        log_success "✅ Ingress controller opérationnel ($ready_ingress pod(s))"
    else
        log_error "❌ Ingress controller non opérationnel"
        return 1
    fi
    
    # Test simple de connectivité HTTP (port 80 doit être ouvert)
    if netstat -an | grep -q ":80.*LISTEN"; then
        log_success "🚪 Port 80 exposé par l'ingress"
    else
        log_warning "⚠️  Port 80 non exposé"
    fi
    
    return 0
}

# Test de la configuration de la registry dans le cluster
test_registry_config() {
    log_info "⚙️  === Test de la configuration registry ==="
    
    # Vérifier la ConfigMap local-registry-hosting
    if kubectl get configmap -n kube-public local-registry-hosting \
        --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1; then
        log_success "✅ ConfigMap local-registry-hosting présente"
        
        # Vérifier le contenu
        local registry_host=$(kubectl get configmap -n kube-public local-registry-hosting \
            --context "kind-${CLUSTER_NAME}" -o jsonpath='{.data.localRegistryHosting\.v1}' 2>/dev/null | \
            grep -o "localhost:${REGISTRY_PORT}" || echo "")
        
        if [ -n "$registry_host" ]; then
            log_success "📝 Configuration registry correcte (${registry_host})"
        else
            log_warning "⚠️  Configuration registry incomplète"
        fi
    else
        log_error "❌ ConfigMap local-registry-hosting manquante"
        return 1
    fi
    
    return 0
}

# Test des montages de pods sources
test_pod_mounts() {
    log_info "📁 === Test des montages de pods sources ==="
    
    # Vérifier que les répertoires sont montés dans les nodes
    local control_plane_node="kind-${CLUSTER_NAME}-control-plane"
    
    if docker exec "$control_plane_node" test -d /pods 2>/dev/null; then
        log_success "✅ Répertoire /pods monté dans le control-plane"
        
        # Lister les pods montés
        local mounted_pods=$(docker exec "$control_plane_node" ls /pods 2>/dev/null | tr '\n' ' ')
        if [ -n "$mounted_pods" ]; then
            log_success "📂 Pods montés: $mounted_pods"
            
            # Vérifier quelques fichiers dans chaque pod
            for pod in $mounted_pods; do
                if docker exec "$control_plane_node" test -f "/pods/${pod}/README.md" 2>/dev/null; then
                    log_success "📄 README.md trouvé dans ${pod}"
                fi
            done
        else
            log_warning "⚠️  Aucun pod monté dans /pods"
        fi
    else
        log_error "❌ Répertoire /pods non monté dans le control-plane"
        return 1
    fi
    
    return 0
}

# Afficher le résumé des tests
show_test_summary() {
    local registry_ok=$1
    local k8s_ok=$2
    local ingress_ok=$3
    local config_ok=$4
    local mounts_ok=$5
    
    log_info "📊 === Résumé des tests ==="
    [ "$registry_ok" -eq 0 ] && log_success "✅ Registry locale" || log_error "❌ Registry locale"
    [ "$k8s_ok" -eq 0 ] && log_success "✅ Cluster Kubernetes" || log_error "❌ Cluster Kubernetes"
    [ "$ingress_ok" -eq 0 ] && log_success "✅ Ingress controller" || log_error "❌ Ingress controller"
    [ "$config_ok" -eq 0 ] && log_success "✅ Configuration registry" || log_error "❌ Configuration registry"
    [ "$mounts_ok" -eq 0 ] && log_success "✅ Montages pods sources" || log_error "❌ Montages pods sources"
    
    echo ""
    if [ "$registry_ok" -eq 0 ] && [ "$k8s_ok" -eq 0 ] && [ "$ingress_ok" -eq 0 ] && [ "$config_ok" -eq 0 ] && [ "$mounts_ok" -eq 0 ]; then
        log_success "🎉 Tous les tests sont passés avec succès !"
        echo "   ✨ L'environnement kind est complètement opérationnel."
        echo "   📁 Les sources pods sont montées et accessibles."
    else
        log_error "💥 Certains tests ont échoué"
        echo "   🔍 Vérifiez les logs ci-dessus pour diagnostiquer les problèmes."
        echo "   🔧 Essayez de recréer l'environnement avec ./start-kind.sh"
        echo "   📁 Pour vérifier les montages: ./check-pod-mounts.sh"
    fi
}

# Fonction principale
main() {
    log_info "🧪 === Tests de l'environnement kind '${CLUSTER_NAME}' ==="
    echo ""
    
    local registry_result=1
    local k8s_result=1
    local ingress_result=1
    local config_result=1
    local mounts_result=1
    
    # Exécuter les tests
    test_local_registry && registry_result=0
    echo ""
    
    test_kubernetes_cluster && k8s_result=0
    echo ""
    
    test_ingress_controller && ingress_result=0
    echo ""
    
    test_registry_config && config_result=0
    echo ""
    
    test_pod_mounts && mounts_result=0
    echo ""
    
    # Afficher le résumé
    show_test_summary $registry_result $k8s_result $ingress_result $config_result $mounts_result
    
    # Code de sortie basé sur les résultats
    if [ "$registry_result" -eq 0 ] && [ "$k8s_result" -eq 0 ] && [ "$ingress_result" -eq 0 ] && [ "$config_result" -eq 0 ] && [ "$mounts_result" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Exécuter le script principal
main "$@"
