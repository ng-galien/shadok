#!/bin/bash

# Script idempotent pour démarrer kind avec registry mirror GitHub
# Usage: ./start-kind.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
REGISTRY_NAME="shadok-registry"
REGISTRY_PORT="5001"
GITHUB_REGISTRY="ghcr.io"

# Chemin vers le répertoire des pods (relatif au script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PODS_DIR="$(dirname "${SCRIPT_DIR}")/pods"

# Validation du répertoire pods
if [ ! -d "${PODS_DIR}" ]; then
    echo "❌ Erreur: Répertoire pods non trouvé: ${PODS_DIR}"
    exit 1
fi

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

# Vérifier les prérequis
check_prerequisites() {
    log_info "🔍 Vérification des prérequis..."
    
    if ! command -v kind &> /dev/null; then
        log_error "❌ kind n'est pas installé. Installez-le avec: brew install kind"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "❌ docker n'est pas installé"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "❌ Docker n'est pas démarré"
        exit 1
    fi
    
    log_success "✅ Prérequis vérifiés"
}

# Nettoyer le cluster existant si nécessaire
cleanup_existing_cluster() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "⚠️  Cluster kind '${CLUSTER_NAME}' existant détecté"
        log_info "🗑️  Suppression du cluster existant..."
        kind delete cluster --name "${CLUSTER_NAME}"
        log_success "🧹 Cluster existant supprimé"
    fi
}

# Nettoyer la registry existante si nécessaire
cleanup_existing_registry() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        log_warning "⚠️  Registry '${REGISTRY_NAME}' existante détectée"
        log_info "🗑️  Suppression de la registry existante..."
        docker rm -f "${REGISTRY_NAME}" || true
        log_success "🧹 Registry existante supprimée"
    fi
}

# Créer la registry locale
create_local_registry() {
    log_info "🐳 Création de la registry locale..."
    
    docker run -d \
        --restart=always \
        --name "${REGISTRY_NAME}" \
        -p "${REGISTRY_PORT}:5000" \
        registry:2
    
    log_success "📦 Registry locale créée sur le port ${REGISTRY_PORT}"
}

# Créer la configuration kind
create_kind_config() {
    log_info "⚙️  Création de la configuration kind..."
    
    # Découvrir automatiquement les pods disponibles
    local pods_mounts=""
    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            # Ignorer les répertoires build et node_modules
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                pods_mounts="${pods_mounts}  - hostPath: ${pod_dir}
    containerPath: /pods/${pod_name}
    readOnly: true
"
            fi
        fi
    done
    
    log_info "📁 Montage des répertoires pods détectés :"
    echo "${pods_mounts}" | grep "hostPath:" | sed 's/.*hostPath: /  - /'
    
    cat > /tmp/kind-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  extraMounts:
${pods_mounts}
- role: worker
  extraMounts:
${pods_mounts}
- role: worker
  extraMounts:
${pods_mounts}
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
      endpoint = ["http://${REGISTRY_NAME}:5000"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${GITHUB_REGISTRY}"]
      endpoint = ["https://${GITHUB_REGISTRY}"]
EOF
    
    log_success "📝 Configuration kind créée"
}

# Créer le cluster kind
create_kind_cluster() {
    log_info "🚀 Création du cluster kind '${CLUSTER_NAME}'..."
    
    kind create cluster --config /tmp/kind-config.yaml
    
    log_success "🎯 Cluster kind '${CLUSTER_NAME}' créé"
}

# Connecter la registry au cluster
connect_registry_to_cluster() {
    log_info "🔗 Connexion de la registry au cluster..."
    
    # Connecter la registry au réseau kind
    if ! docker network ls | grep -q kind; then
        log_error "❌ Réseau kind non trouvé"
        exit 1
    fi
    
    docker network connect "kind" "${REGISTRY_NAME}" || true
    
    # Documenter la registry locale dans le cluster
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
    
    log_success "🎪 Registry connectée au cluster"
}

# Installer les contrôleurs essentiels
install_controllers() {
    log_info "🛠️  Installation des contrôleurs essentiels..."
    
    # Installer NGINX Ingress Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    # Attendre que l'ingress controller soit prêt
    log_info "⏳ Attente du démarrage de l'ingress controller..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s
    
    log_success "🌐 Contrôleurs installés"
}

# Créer les PersistentVolumes pour les pods sources
create_pod_persistent_volumes() {
    log_info "💾 Création des PersistentVolumes pour les sources pods..."
    
    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            # Ignorer les répertoires build et node_modules
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                log_info "📁 Création du PV pour ${pod_name}..."
                
                kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${pod_name}-sources
  labels:
    app: shadok
    pod: ${pod_name}
    type: sources
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /pods/${pod_name}
    type: Directory
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${pod_name}-sources
  namespace: default
  labels:
    app: shadok
    pod: ${pod_name}
    type: sources
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-storage
  selector:
    matchLabels:
      pod: ${pod_name}
      type: sources
EOF
            fi
        fi
    done
    
    log_success "✅ PersistentVolumes créés pour les sources pods"
}

# Afficher les informations finales
show_cluster_info() {
    log_success "🎉 === Cluster kind '${CLUSTER_NAME}' prêt ! ==="
    echo ""
    log_info "🔧 Configuration:"
    echo "  - 🏷️  Cluster: ${CLUSTER_NAME}"
    echo "  - 📦 Registry locale: localhost:${REGISTRY_PORT}"
    echo "  - 🐙 GitHub registry mirror: ${GITHUB_REGISTRY}"
    echo ""
    log_info "� Pods sources montés (readonly):"
    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                echo "  - 📂 ${pod_name}: /pods/${pod_name}"
            fi
        fi
    done
    echo ""
    log_info "�📋 Commandes utiles:"
    echo "  - kubectl cluster-info"
    echo "  - kubectl get nodes"
    echo "  - kubectl get pv,pvc"
    echo "  - docker push localhost:${REGISTRY_PORT}/mon-image:tag"
    echo ""
    log_info "💾 PersistentVolumes:"
    echo "  - kubectl get pv -l app=shadok"
    echo "  - kubectl get pvc -l app=shadok"
    echo ""
    log_info "🧹 Pour nettoyer:"
    echo "  - kind delete cluster --name ${CLUSTER_NAME}"
    echo "  - docker rm -f ${REGISTRY_NAME}"
    echo ""
    
    # Afficher l'état des nodes
    kubectl get nodes -o wide
    echo ""
    
    # Afficher l'état des PV/PVC
    log_info "📊 État des PersistentVolumes:"
    kubectl get pv -l app=shadok 2>/dev/null || log_warning "Aucun PV shadok trouvé"
    echo ""
    kubectl get pvc -l app=shadok 2>/dev/null || log_warning "Aucun PVC shadok trouvé"
}

# Fonction principale
main() {
    log_info "🚀 === Démarrage de kind avec registry mirror GitHub ==="
    echo ""
    
    check_prerequisites
    cleanup_existing_cluster
    cleanup_existing_registry
    create_local_registry
    
    # Attendre que la registry soit prête
    sleep 2
    
    create_kind_config
    create_kind_cluster
    connect_registry_to_cluster
    install_controllers
    create_pod_persistent_volumes
    
    # Nettoyer le fichier de config temporaire
    rm -f /tmp/kind-config.yaml
    
    show_cluster_info
}

# Exécuter le script principal
main "$@"
