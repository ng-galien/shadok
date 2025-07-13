#!/bin/bash

# Script pour vérifier les montages de pods dans kind
# Usage: ./check-pod-mounts.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"

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

# Vérifier les montages dans les nodes
check_node_mounts() {
    log_info "📁 === Vérification des montages dans les nodes ==="
    
    local nodes=$(kubectl get nodes --context "kind-${CLUSTER_NAME}" -o name 2>/dev/null | sed 's|node/||')
    
    for node in $nodes; do
        log_info "🖥️  Vérification du node: ${node}"
        
        # Exécuter une commande dans le node pour lister les montages /pods
        docker exec "${node}" ls -la /pods/ 2>/dev/null && {
            log_success "✅ Répertoire /pods trouvé dans ${node}"
            echo ""
            log_info "📂 Contenu de /pods dans ${node}:"
            docker exec "${node}" find /pods -maxdepth 2 -type d 2>/dev/null | head -20
        } || {
            log_warning "⚠️  Répertoire /pods non trouvé dans ${node}"
        }
        echo ""
    done
}

# Vérifier les PersistentVolumes
check_persistent_volumes() {
    log_info "💾 === Vérification des PersistentVolumes ==="
    
    local pvs=$(kubectl get pv -l app=shadok --context "kind-${CLUSTER_NAME}" -o name 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$pvs" -gt 0 ]; then
        log_success "✅ ${pvs} PersistentVolume(s) shadok trouvé(s)"
        echo ""
        kubectl get pv -l app=shadok --context "kind-${CLUSTER_NAME}" 2>/dev/null
        echo ""
        
        log_info "📋 Détails des PV:"
        kubectl get pv -l app=shadok --context "kind-${CLUSTER_NAME}" -o custom-columns="NAME:.metadata.name,POD:.metadata.labels.pod,PATH:.spec.hostPath.path,STATUS:.status.phase" 2>/dev/null
    else
        log_warning "⚠️  Aucun PersistentVolume shadok trouvé"
    fi
}

# Vérifier les PersistentVolumeClaims
check_persistent_volume_claims() {
    log_info "📋 === Vérification des PersistentVolumeClaims ==="
    
    local pvcs=$(kubectl get pvc -l app=shadok --context "kind-${CLUSTER_NAME}" -o name 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$pvcs" -gt 0 ]; then
        log_success "✅ ${pvcs} PersistentVolumeClaim(s) shadok trouvé(s)"
        echo ""
        kubectl get pvc -l app=shadok --context "kind-${CLUSTER_NAME}" 2>/dev/null
        echo ""
        
        log_info "📋 Détails des PVC:"
        kubectl get pvc -l app=shadok --context "kind-${CLUSTER_NAME}" -o custom-columns="NAME:.metadata.name,POD:.metadata.labels.pod,STATUS:.status.phase,VOLUME:.spec.volumeName" 2>/dev/null
    else
        log_warning "⚠️  Aucun PersistentVolumeClaim shadok trouvé"
    fi
}

# Tester l'accès aux sources depuis un pod
test_pod_access() {
    log_info "🧪 === Test d'accès aux sources depuis un pod ==="
    
    # Créer un pod de test temporaire
    local test_pod_yaml="/tmp/test-sources-access-${CLUSTER_NAME}.yaml"
    cat > "$test_pod_yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-sources-access
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ['sleep', '300']
    volumeMounts:
    - name: node-hello-sources
      mountPath: /mnt/node-hello
      readOnly: true
    - name: python-hello-sources
      mountPath: /mnt/python-hello
      readOnly: true
    - name: quarkus-hello-sources
      mountPath: /mnt/quarkus-hello
      readOnly: true
  volumes:
  - name: node-hello-sources
    persistentVolumeClaim:
      claimName: pvc-node-hello-sources
  - name: python-hello-sources
    persistentVolumeClaim:
      claimName: pvc-python-hello-sources
  - name: quarkus-hello-sources
    persistentVolumeClaim:
      claimName: pvc-quarkus-hello-sources
  restartPolicy: Never
EOF
    
    log_info "🚀 Déploiement du pod de test..."
    if kubectl apply -f "$test_pod_yaml" --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1; then
        log_success "✅ Pod de test déployé"
        
        # Attendre que le pod soit prêt
        if kubectl wait --for=condition=Ready pod/test-sources-access \
            --context "kind-${CLUSTER_NAME}" --timeout=60s > /dev/null 2>&1; then
            
            log_info "🔍 Test d'accès aux sources montées:"
            
            # Tester l'accès à chaque pod
            for pod_type in node-hello python-hello quarkus-hello; do
                echo ""
                log_info "📂 Test accès ${pod_type}:"
                if kubectl exec test-sources-access --context "kind-${CLUSTER_NAME}" -- ls -la "/mnt/${pod_type}" 2>/dev/null; then
                    log_success "✅ Accès réussi à ${pod_type}"
                    
                    # Afficher quelques fichiers
                    kubectl exec test-sources-access --context "kind-${CLUSTER_NAME}" -- find "/mnt/${pod_type}" -maxdepth 2 -type f | head -5 2>/dev/null || true
                else
                    log_warning "⚠️  Impossible d'accéder à ${pod_type}"
                fi
            done
        else
            log_warning "⚠️  Pod de test non prêt dans les temps"
        fi
        
        # Nettoyer
        kubectl delete -f "$test_pod_yaml" --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1 || true
        rm -f "$test_pod_yaml"
        log_success "🧹 Pod de test nettoyé"
    else
        log_error "❌ Échec du déploiement du pod de test"
        rm -f "$test_pod_yaml"
    fi
}

# Afficher un résumé des commandes utiles
show_useful_commands() {
    log_info "🛠️  === Commandes utiles pour les sources pods ==="
    echo ""
    echo "# 📁 Vérifier les montages dans les nodes:"
    echo "  docker exec kind-${CLUSTER_NAME}-control-plane ls -la /pods/"
    echo "  docker exec kind-${CLUSTER_NAME}-worker ls -la /pods/"
    echo ""
    echo "# 💾 Gérer les PersistentVolumes:"
    echo "  kubectl get pv -l app=shadok"
    echo "  kubectl describe pv pv-node-hello-sources"
    echo ""
    echo "# 📋 Gérer les PersistentVolumeClaims:"
    echo "  kubectl get pvc -l app=shadok"
    echo "  kubectl describe pvc pvc-node-hello-sources"
    echo ""
    echo "# 🧪 Tester l'accès depuis un pod:"
    echo "  kubectl run test-pod --image=busybox --rm -it -- sh"
    echo "  # Puis dans le pod:"
    echo "  # ls -la /mnt/sources/"
}

# Fonction principale
main() {
    log_info "🔍 === Vérification des montages de pods dans kind '${CLUSTER_NAME}' ==="
    echo ""
    
    # Vérifier si le cluster existe
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_error "❌ Cluster kind '${CLUSTER_NAME}' non trouvé"
        echo "   🚀 Utilisez ./start-kind.sh pour créer le cluster"
        exit 1
    fi
    
    check_node_mounts
    echo ""
    
    check_persistent_volumes
    echo ""
    
    check_persistent_volume_claims
    echo ""
    
    test_pod_access
    echo ""
    
    show_useful_commands
}

# Exécuter le script principal
main "$@"
