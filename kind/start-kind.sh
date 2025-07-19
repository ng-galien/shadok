#!/bin/bash

# Idempotent script to start kind with GitHub registry mirror
# Usage: ./start-kind.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
REGISTRY_NAME="shadok-registry"
REGISTRY_PORT="5001"

# Path to the pods directory (relative to the script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PODS_DIR="$(dirname "${SCRIPT_DIR}")/pods"

# Validation of the pods directory
if [ ! -d "${PODS_DIR}" ]; then
    echo "❌ Error: Pods directory not found: ${PODS_DIR}"
    exit 1
fi

# Colors for logs
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

# Check prerequisites
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."

    if ! command -v kind &> /dev/null; then
        log_error "❌ kind is not installed. Install it with: brew install kind"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        log_error "❌ docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "❌ Docker is not running"
        exit 1
    fi

    log_success "✅ Prerequisites verified"
}

# Clean up existing cluster if necessary
cleanup_existing_cluster() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "⚠️  Existing kind cluster '${CLUSTER_NAME}' detected"
        log_info "🗑️  Deleting existing cluster..."
        kind delete cluster --name "${CLUSTER_NAME}"
        log_success "🧹 Existing cluster deleted"
    fi
}

# Clean up existing registry if necessary (preserve data)
cleanup_existing_registry() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        log_warning "⚠️  Existing registry '${REGISTRY_NAME}' detected"
        if docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
            log_info "⏹️  Stopping existing registry..."
            docker stop "${REGISTRY_NAME}" || true
        fi
        log_info "🗑️  Removing container (data preserved)..."
        docker rm "${REGISTRY_NAME}" || true
        log_success "🧹 Registry container removed (data preserved)"
    fi
}

# Create the local registry
create_local_registry() {
    log_info "🐳 Creating local registry..."

    # Create directory for the registry persistent volume
    local registry_volume_dir="${HOME}/.shadok/registry-data"
    mkdir -p "${registry_volume_dir}"

    docker run -d \
        --restart=always \
        --name "${REGISTRY_NAME}" \
        -p "${REGISTRY_PORT}:5000" \
        -v "${registry_volume_dir}:/var/lib/registry" \
        registry:2

    log_success "📦 Local registry created on port ${REGISTRY_PORT}"
    log_info "💾 Persistent volume: ${registry_volume_dir}"
}

# Create the kind configuration
create_kind_config() {
    log_info "⚙️  Creating kind configuration..."

    # Automatically discover available pods
    local pods_mounts=""
    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            # Ignore build and node_modules directories
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                pods_mounts="${pods_mounts}  - hostPath: ${pod_dir}
    containerPath: /pods/${pod_name}
    readOnly: true
"
            fi
        fi
    done

    log_info "📁 Mounting detected pod directories:"
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
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
      endpoint = ["http://${REGISTRY_NAME}:5000"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["http://${REGISTRY_NAME}:5000"]
EOF

    log_success "📝 Kind configuration created"
}

# Create the kind cluster
create_kind_cluster() {
    log_info "🚀 Creating kind cluster '${CLUSTER_NAME}'..."

    kind create cluster --config /tmp/kind-config.yaml

    log_success "🎯 Kind cluster '${CLUSTER_NAME}' created"
}

# Connect the registry to the cluster
connect_registry_to_cluster() {
    log_info "🔗 Connecting registry to the cluster..."

    # Wait for the cluster to be fully initialized
    sleep 3

    # Check if the kind network exists
    if ! docker network ls | grep -q "kind"; then
        log_warning "⚠️  Kind network not found, attempting to create..."
        # The network should normally be created by kind, but we can create it manually if needed
        docker network create kind --driver bridge || log_warning "Kind network may already exist"
    fi

    # Connect the registry to the kind network
    if docker network connect "kind" "${REGISTRY_NAME}" 2>/dev/null; then
        log_success "🔗 Registry connected to kind network"
    else
        log_warning "⚠️  Registry already connected to kind network"
    fi

    # Document the local registry in the cluster
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

    log_success "🎪 Registry connected to cluster"
}

# Install essential controllers
install_controllers() {
    log_info "🛠️  Installing essential controllers..."

    # Install NGINX Ingress Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    # Wait for the ingress controller to be ready
    log_info "⏳ Waiting for ingress controller to start..."

    # First wait for the admission patch job to complete
    kubectl wait --namespace ingress-nginx \
        --for=condition=complete job/ingress-nginx-admission-patch \
        --timeout=90s

    # Then wait for the controller pods to be ready
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s

    # Patch the ConfigMap to enable snippets
    log_info "🔧 Enabling snippets for ingress-nginx..."
    kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
        --patch '{"data":{"allow-snippet-annotations":"true","annotations-risk-level":"Critical"}}'

    # Restart the controller to apply changes
    log_info "🔄 Restarting ingress-nginx controller..."
    kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx

    # Wait for the restart to complete
    log_info "⏳ Waiting for controller to restart..."
    kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=90s

    log_success "🌐 Controllers installed with snippets enabled"
}

# Install cert-manager
install_cert_manager() {
    log_info "🔒 Installing cert-manager..."

    # Check if cert-manager is already installed
    if kubectl get namespace cert-manager > /dev/null 2>&1; then
        log_warning "⚠️  cert-manager seems to be already installed, cleaning up..."

        # Delete existing cert-manager resources
        kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml --ignore-not-found=true || true

        # Delete the cert-manager namespace and wait for it to be completely removed
        kubectl delete namespace cert-manager --wait=true || true

        # Wait for the namespace to be completely removed
        log_info "⏳ Waiting for complete removal of cert-manager namespace..."
        while kubectl get namespace cert-manager > /dev/null 2>&1; do
            log_info "  Waiting..."
            sleep 5
        done

        log_success "🧹 Old cert-manager cleaned up"
    fi

    # Create the cert-manager namespace
    kubectl create namespace cert-manager

    # Install cert-manager with Helm
    log_info "📦 Installing cert-manager with Helm..."

    # Check if Helm is installed
    if ! command -v helm > /dev/null 2>&1; then
        log_error "❌ Helm is not installed. Installing cert-manager with kubectl..."

        # Install cert-manager with kubectl as fallback
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.1/cert-manager.yaml
    else
        # Add the cert-manager Helm repo
        helm repo add jetstack https://charts.jetstack.io
        helm repo update

        # Install cert-manager with Helm
        helm install \
            cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --version v1.13.1 \
            --set installCRDs=true
    fi

    # Wait for cert-manager to be ready
    log_info "⏳ Waiting for cert-manager to start..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=120s

    log_success "🔒 cert-manager successfully installed"
}

# Create PersistentVolumes for pod sources
create_pod_persistent_volumes() {
    log_info "💾 Creating PersistentVolumes for pod sources..."

    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            # Ignore build and node_modules directories
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                log_info "📁 Creating PV for ${pod_name}..."

                # First create the shadok namespace if it doesn't exist
                kubectl create namespace shadok --dry-run=client -o yaml | kubectl apply -f -

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
  namespace: shadok
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

    log_success "✅ PersistentVolumes created for pod sources"
}

# Create cache volume for dependencies
create_cache_volume() {
    log_info "💾 Creating cache volume for dependencies..."

    # Create directory for the cache volume
    docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /tmp/shadok-application-cache
    docker exec "${CLUSTER_NAME}-control-plane" chmod 777 /tmp/shadok-application-cache

    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-shadok-cache
  labels:
    app: shadok
    type: cache
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /tmp/shadok-application-cache
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${CLUSTER_NAME}-control-plane
EOF

    log_success "✅ Cache volume created"
}

# Display final information
show_cluster_info() {
    log_success "🎉 === Kind cluster '${CLUSTER_NAME}' ready! ==="
    echo ""
    log_info "🔧 Configuration:"
    echo "  - 🏷️  Cluster: ${CLUSTER_NAME}"
    echo "  - 📦 Local registry: localhost:${REGISTRY_PORT} (mirrors docker.io)"
    echo ""
    log_info "� Pod sources mounted (readonly):"
    for pod_dir in "${PODS_DIR}"/*/; do
        if [ -d "$pod_dir" ]; then
            local pod_name=$(basename "$pod_dir")
            if [[ "$pod_name" != "build" && "$pod_name" != "node_modules" ]]; then
                echo "  - 📂 ${pod_name}: /pods/${pod_name}"
            fi
        fi
    done
    echo ""
    log_info "�📋 Useful commands:"
    echo "  - kubectl cluster-info"
    echo "  - kubectl get nodes"
    echo "  - kubectl get pv,pvc"
    echo "  - docker push localhost:${REGISTRY_PORT}/my-image:tag"
    echo ""
    log_info "💾 PersistentVolumes:"
    echo "  - kubectl get pv -l app=shadok"
    echo "  - kubectl get pvc -l app=shadok"
    echo ""
    log_info "🗄️ Cache volume:"
    echo "  - PV: pv-shadok-cache"
    echo ""
    log_info "🧹 To clean up:"
    echo "  - kind delete cluster --name ${CLUSTER_NAME}"
    echo "  - docker rm -f ${REGISTRY_NAME}"
    echo "  - rm -rf ~/.shadok/registry-data  # Remove image cache"
    echo "  - rm -rf /tmp/shadok-cache  # Remove dependency cache"
    echo ""

    # Display node status
    kubectl get nodes -o wide
    echo ""

    # Display PV/PVC status
    log_info "📊 PersistentVolumes status:"
    kubectl get pv -l app=shadok 2>/dev/null || log_warning "No shadok PV found"
    echo ""
    kubectl get pvc -l app=shadok 2>/dev/null || log_warning "No shadok PVC found"
}

# Main function
main() {
    log_info "🚀 === Starting kind with GitHub and Docker Hub registry mirrors ==="
    echo ""

    check_prerequisites
    cleanup_existing_cluster
    cleanup_existing_registry
    create_local_registry
    create_kind_config
    create_kind_cluster
    connect_registry_to_cluster
    install_controllers
    install_cert_manager
    create_pod_persistent_volumes
    create_cache_volume

    # Advanced cluster configuration
    log_info "🔧 Launching advanced configuration..."
    if [ -x "./kind-config.sh" ]; then
        ./kind-config.sh "${CLUSTER_NAME}"
    else
        log_warning "⚠️  Script kind-config.sh not found or not executable"
        log_info "   Run manually: ./kind-config.sh ${CLUSTER_NAME}"
    fi

    # Clean up temporary config file
    rm -f /tmp/kind-config.yaml

    show_cluster_info
}

# Execute the main script
main "$@"
