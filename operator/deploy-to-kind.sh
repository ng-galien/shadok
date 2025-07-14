#!/bin/bash

# 🚀 Deploy Shadok Operator to Kind - Complete Automation
# ================================================================
#
# Ce script automatise complètement le déploiement de l'opérateur Shadok
# dans un cluster Kind avec toutes les dépendances requises.
#
# Fonctionnalités :
# - Configuration et démarrage du cluster Kind
# - Construction et déploiement de l'image de l'opérateur
# - Déploiement des CRDs et RBAC
# - Configuration du webhook de mutation
# - Déploiement des ressources de test
# - Validation complète du déploiement
#
# Usage: ./deploy-to-kind.sh [options]

set -e

# ========================================
# 🎨 Configuration et Variables
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration par défaut
CLUSTER_NAME="shadok-dev"
NAMESPACE="shadok"
REGISTRY="localhost:5001"
IMAGE_NAME="shadok/operator"
IMAGE_TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Options configurables
REBUILD_IMAGE=true
REDEPLOY_CLUSTER=false
SKIP_TESTS=false
VERBOSE=false
WAIT_TIMEOUT=300

print_header() {
    echo -e "\n${PURPLE}===============================================${NC}"
    echo -e "${PURPLE} 🚀 $1${NC}"
    echo -e "${PURPLE}===============================================${NC}\n"
}

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}🔍 $1${NC}"
    fi
}

# ========================================
# 🔧 Fonctions utilitaires
# ========================================

check_prerequisites() {
    print_header "Vérification des Prérequis"

    local missing_tools=()

    # Vérifier les outils requis
    for tool in kind kubectl docker gradle; do
        if ! command -v $tool > /dev/null 2>&1; then
            missing_tools+=($tool)
        else
            log_verbose "$tool ✓"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Outils manquants: ${missing_tools[*]}"
        print_error "Installez les outils requis avant de continuer"
        exit 1
    fi

    # Vérifier que Docker est en cours d'exécution
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker n'est pas en cours d'exécution"
        exit 1
    fi

    print_success "Tous les prérequis sont satisfaits"
}

wait_for_condition() {
    local description="$1"
    local condition_cmd="$2"
    local timeout="${3:-60}"
    local interval="${4:-5}"

    print_step "Attente: $description (max ${timeout}s)"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition_cmd" > /dev/null 2>&1; then
            print_success "$description - Prêt !"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))

        if [ $((elapsed % 30)) -eq 0 ]; then
            log_verbose "Attente en cours... ${elapsed}/${timeout}s"
        fi
    done

    print_error "$description - Timeout après ${timeout}s"
    return 1
}

# ========================================
# 🏗️ Gestion du Cluster Kind
# ========================================

setup_kind_cluster() {
    print_header "Configuration du Cluster Kind"

    # Vérifier si le cluster existe déjà
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        if [ "$REDEPLOY_CLUSTER" = true ]; then
            print_step "Suppression du cluster existant..."
            kind delete cluster --name "$CLUSTER_NAME"
            print_success "Cluster supprimé"
        else
            print_success "Cluster '$CLUSTER_NAME' existe déjà"
            return 0
        fi
    fi

    # Créer le cluster avec la configuration personnalisée
    print_step "Création du cluster Kind avec ingress et registry..."

    cat << EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
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
  - containerPort: 5001
    hostPort: 5001
    protocol: TCP
  extraMounts:
  - hostPath: /tmp/shadok-sources
    containerPath: /tmp/shadok-sources
  - hostPath: /tmp/shadok-java-cache
    containerPath: /tmp/shadok-java-cache
EOF

    print_success "Cluster Kind créé"

    # Attendre que le cluster soit prêt
    wait_for_condition "Cluster prêt" "kubectl cluster-info --context kind-${CLUSTER_NAME}" 60
}

setup_ingress_controller() {
    print_header "Installation du Contrôleur Ingress"

    print_step "Déploiement de Nginx Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    # Attendre que l'ingress controller soit prêt
    wait_for_condition "Ingress Controller prêt" \
        "kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --field-selector=status.phase=Running | grep -q Running" \
        120 10

    print_success "Nginx Ingress Controller déployé"
}

setup_local_registry() {
    print_header "Configuration du Registre Local"

    # Vérifier si le registre existe déjà
    if docker ps | grep -q "kind-registry"; then
        print_success "Registre local déjà en cours d'exécution"
        return 0
    fi

    print_step "Démarrage du registre Docker local..."

    # Démarrer le registre local
    docker run -d --restart=always -p "5001:5000" --name "kind-registry" registry:2 || {
        print_warning "Le registre semble déjà exister, tentative de redémarrage..."
        docker start kind-registry || {
            print_error "Impossible de démarrer le registre"
            return 1
        }
    }

    # Connecter le registre au réseau Kind
    if ! docker network ls | grep -q "kind"; then
        docker network create kind || true
    fi

    docker network connect "kind" "kind-registry" 2>/dev/null || true

    # Configurer le cluster pour utiliser le registre local
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:5001"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

    print_success "Registre local configuré sur localhost:5001"
}

# ========================================
# 📦 Construction et Déploiement de l'Image
# ========================================

build_operator_image() {
    print_header "Construction de l'Image de l'Opérateur"

    if [ "$REBUILD_IMAGE" = false ]; then
        print_step "Vérification de l'existence de l'image..."
        if docker images | grep -q "$IMAGE_NAME.*$IMAGE_TAG"; then
            print_success "Image existe déjà, construction ignorée"
            return 0
        fi
    fi

    print_step "Construction de l'image Shadok Operator..."

    # Construire l'image avec Gradle
    print_step "Construction avec Gradle et Docker..."
    ./gradlew build -x test || {
        print_error "Échec de la construction Gradle"
        exit 1
    }

    # Construire l'image Docker
    docker build -f Dockerfile.gradle -t "$FULL_IMAGE" . || {
        print_error "Échec de la construction Docker"
        exit 1
    }

    print_success "Image construite: $FULL_IMAGE"

    # Pousser vers le registre local
    print_step "Push vers le registre local..."
    docker push "$FULL_IMAGE" || {
        print_error "Échec du push vers le registre"
        exit 1
    }

    print_success "Image poussée vers $REGISTRY"
}

# ========================================
# ☸️ Déploiement Kubernetes
# ========================================

create_namespace() {
    print_header "Création du Namespace"

    print_step "Création du namespace '$NAMESPACE'..."

    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
  labels:
    name: $NAMESPACE
    app.kubernetes.io/name: shadok
    app.kubernetes.io/part-of: shadok-operator
EOF

    print_success "Namespace '$NAMESPACE' créé"
}

deploy_persistent_volumes() {
    print_header "Déploiement des Volumes Persistants"

    print_step "Création des répertoires sur le nœud Kind..."

    # Créer les répertoires dans le conteneur Kind
    docker exec "${CLUSTER_NAME}-control-plane" mkdir -p /tmp/shadok-sources /tmp/shadok-java-cache
    docker exec "${CLUSTER_NAME}-control-plane" chmod 777 /tmp/shadok-sources /tmp/shadok-java-cache

    print_step "Déploiement des PersistentVolumes..."

    # PV pour les sources
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-shadok-sources
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /tmp/shadok-sources
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${CLUSTER_NAME}-control-plane
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-java-cache
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /tmp/shadok-java-cache
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${CLUSTER_NAME}-control-plane
EOF

    print_success "PersistentVolumes déployés"
}

deploy_crds() {
    print_header "Déploiement des Custom Resource Definitions"
    
    print_step "Application des CRDs Shadok..."
    
    # Appliquer les ressources générées par Quarkus
    if [ -d "build/kubernetes" ]; then
        kubectl apply -f build/kubernetes/kubernetes.yml || {
            print_error "Échec du déploiement des ressources"
            exit 1
        }
    else
        print_error "Répertoire build/kubernetes non trouvé"
        exit 1
    fi

    # Attendre que les CRDs soient établis
    for crd in applications.shadok.org projectsources.shadok.org dependencycaches.shadok.org; do
        wait_for_condition "CRD $crd établi" \
            "kubectl get crd $crd -o jsonpath='{.status.conditions[?(@.type==\"Established\")].status}' | grep -q True" \
            60
    done

    print_success "CRDs déployés et établis"
}

deploy_rbac() {
    print_header "Configuration RBAC"

    print_step "Création du ServiceAccount et RBAC..."

    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shadok-operator
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: shadok-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims", "persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["shadok.org"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["admissionregistration.k8s.io"]
  resources: ["mutatingwebhookconfigurations"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: shadok-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: shadok-operator
subjects:
- kind: ServiceAccount
  name: shadok-operator
  namespace: $NAMESPACE
EOF

    print_success "RBAC configuré"
}

deploy_operator() {
    print_header "Déploiement de l'Opérateur Shadok"

    print_step "Création du Deployment de l'opérateur..."

    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shadok-operator
  namespace: $NAMESPACE
  labels:
    app: shadok-operator
    app.kubernetes.io/name: shadok-operator
    app.kubernetes.io/part-of: shadok
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shadok-operator
  template:
    metadata:
      labels:
        app: shadok-operator
    spec:
      serviceAccountName: shadok-operator
      containers:
      - name: operator
        image: $FULL_IMAGE
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8443
          name: webhook
        env:
        - name: QUARKUS_PROFILE
          value: "prod"
        - name: QUARKUS_KUBERNETES_NAMESPACE
          value: "$NAMESPACE"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /q/health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /q/health/ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: shadok-operator
  namespace: $NAMESPACE
  labels:
    app: shadok-operator
spec:
  selector:
    app: shadok-operator
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: webhook
    port: 443
    targetPort: 8443
  type: ClusterIP
EOF

    # Attendre que l'opérateur soit prêt
    wait_for_condition "Opérateur prêt" \
        "kubectl get pods -n $NAMESPACE -l app=shadok-operator --field-selector=status.phase=Running | grep -q Running" \
        $WAIT_TIMEOUT 10

    print_success "Opérateur Shadok déployé"
}

configure_webhook() {
    print_header "Configuration du Webhook de Mutation"

    print_step "Configuration du MutatingWebhookConfiguration..."

    # Attendre que le service soit disponible
    wait_for_condition "Service opérateur disponible" \
        "kubectl get service shadok-operator -n $NAMESPACE" \
        60

    # Note: Dans un environnement de production, il faudrait générer des certificats TLS
    # Pour Kind/développement, nous utilisons une configuration simplifiée
    cat << EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: shadok-pod-mutator
webhooks:
- name: pod-mutator.shadok.org
  clientConfig:
    service:
      name: shadok-operator
      namespace: $NAMESPACE
      path: /mutate-pods
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1", "v1beta1"]
  sideEffects: None
  failurePolicy: Ignore
EOF

    print_success "Webhook de mutation configuré"
}

# ========================================
# 🧪 Déploiement des Ressources de Test
# ========================================

deploy_test_resources() {
    print_header "Déploiement des Ressources de Test"

    if [ "$SKIP_TESTS" = true ]; then
        print_warning "Tests ignorés"
        return 0
    fi

    print_step "Déploiement des ressources Shadok de test..."

    # Utiliser le fichier de test existant s'il existe
    if [ -f "../pods/quarkus-hello/k8s/shadok-resources.yml" ]; then
        kubectl apply -f ../pods/quarkus-hello/k8s/shadok-resources.yml || {
            print_warning "Échec du déploiement des ressources de test"
        }
    else
        print_warning "Fichier de ressources de test non trouvé"
    fi

    print_success "Ressources de test déployées"
}

deploy_sample_application() {
    print_header "Déploiement d'une Application Exemple"

    if [ "$SKIP_TESTS" = true ]; then
        print_warning "Application exemple ignorée"
        return 0
    fi

    print_step "Déploiement du webservice quarkus-hello..."

    # Déployer quarkus-hello si les manifestes existent
    if [ -d "../pods/quarkus-hello/k8s" ]; then
        kubectl apply -f ../pods/quarkus-hello/k8s/ || {
            print_warning "Échec du déploiement de quarkus-hello"
        }

        # Attendre que l'application soit prête
        wait_for_condition "Application quarkus-hello prête" \
            "kubectl get pods -n $NAMESPACE -l app=quarkus-hello --field-selector=status.phase=Running | grep -q Running" \
            120 10 || {
            print_warning "Application quarkus-hello pas complètement prête"
        }
    else
        print_warning "Manifestes quarkus-hello non trouvés"
    fi

    print_success "Application exemple déployée"
}

# ========================================
# ✅ Validation du Déploiement
# ========================================

validate_deployment() {
    print_header "Validation du Déploiement"

    print_step "Vérification des composants..."

    local issues=0

    # Vérifier les CRDs
    for crd in applications.shadok.org projectsources.shadok.org dependencycaches.shadok.org; do
        if kubectl get crd "$crd" > /dev/null 2>&1; then
            log_verbose "CRD $crd ✓"
        else
            print_error "CRD $crd manquant"
            ((issues++))
        fi
    done

    # Vérifier l'opérateur
    if kubectl get pods -n "$NAMESPACE" -l app=shadok-operator --field-selector=status.phase=Running | grep -q Running; then
        log_verbose "Opérateur en cours d'exécution ✓"
    else
        print_error "Opérateur non démarré"
        ((issues++))
    fi

    # Vérifier le webhook
    if kubectl get mutatingwebhookconfiguration shadok-pod-mutator > /dev/null 2>&1; then
        log_verbose "Webhook configuré ✓"
    else
        print_error "Webhook non configuré"
        ((issues++))
    fi

    # Vérifier les PVs
    if kubectl get pv pv-shadok-sources pv-java-cache > /dev/null 2>&1; then
        log_verbose "PersistentVolumes disponibles ✓"
    else
        print_error "PersistentVolumes manquants"
        ((issues++))
    fi

    if [ $issues -eq 0 ]; then
        print_success "✅ Déploiement validé avec succès !"
        return 0
    else
        print_error "❌ $issues problème(s) détecté(s)"
        return 1
    fi
}

show_deployment_info() {
    print_header "Informations de Déploiement"

    echo "🎯 Cluster Kind: $CLUSTER_NAME"
    echo "📦 Namespace: $NAMESPACE"
    echo "🏷️  Image: $FULL_IMAGE"
    echo "🌐 Registre: $REGISTRY"
    echo ""
    echo "📋 Commandes utiles:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app=shadok-operator"
    echo "  kubectl get applications,projectsources,dependencycaches -n $NAMESPACE"
    echo ""
    echo "🧪 Tests:"
    echo "  ./test-operator.sh"
    echo "  cd operator && ./test-webhook.sh health"
    echo ""
}

# ========================================
# 📚 Aide et Options
# ========================================

show_help() {
    echo "🚀 Deploy Shadok Operator to Kind - Script de Déploiement Complet"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --cluster-name NAME    Nom du cluster Kind (défaut: $CLUSTER_NAME)"
    echo "  --namespace NS         Namespace Kubernetes (défaut: $NAMESPACE)"
    echo "  --image-tag TAG        Tag de l'image (défaut: $IMAGE_TAG)"
    echo "  --no-rebuild           Ne pas reconstruire l'image"
    echo "  --redeploy-cluster     Supprimer et recréer le cluster"
    echo "  --skip-tests           Ignorer le déploiement des ressources de test"
    echo "  --timeout SECS         Timeout d'attente (défaut: $WAIT_TIMEOUT)"
    echo "  --verbose              Logs détaillés"
    echo "  --help                 Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0                          # Déploiement standard"
    echo "  $0 --verbose                # Avec logs détaillés"
    echo "  $0 --redeploy-cluster       # Recréer le cluster"
    echo "  $0 --no-rebuild --skip-tests # Déploiement rapide"
    echo ""
    echo "Prérequis:"
    echo "  • kind, kubectl, docker, gradle installés"
    echo "  • Docker en cours d'exécution"
    echo "  • Ports 80, 443, 5001 disponibles"
    echo ""
}

# ========================================
# 🚀 Fonction Principale
# ========================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                shift 2
                ;;
            --no-rebuild)
                REBUILD_IMAGE=false
                shift
                ;;
            --redeploy-cluster)
                REDEPLOY_CLUSTER=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --timeout)
                WAIT_TIMEOUT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Header
    echo -e "${PURPLE}"
    echo "🚀 ============================================ 🚀"
    echo "   Deploy Shadok Operator to Kind"
    echo "   Déploiement Automatisé Complet"
    echo "=============================================="
    echo -e "${NC}"

    # Démarrer le processus de déploiement
    local start_time=$(date +%s)

    # Étapes du déploiement
    check_prerequisites
    setup_kind_cluster
    setup_local_registry
    setup_ingress_controller
    create_namespace
    deploy_persistent_volumes
    build_operator_image
    deploy_crds
    deploy_rbac
    deploy_operator
    configure_webhook
    deploy_test_resources
    deploy_sample_application

    # Validation finale
    if validate_deployment; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        print_header "🎉 Déploiement Réussi !"
        print_success "Temps total: ${duration}s"
        show_deployment_info

        exit 0
    else
        print_header "❌ Déploiement Échoué"
        print_error "Vérifiez les logs ci-dessus pour diagnostiquer les problèmes"
        exit 1
    fi
}

# Vérifier qu'on est dans le bon répertoire
if [ ! -f "build.gradle.kts" ] || [ ! -d "kubernetes" ]; then
    print_error "Ce script doit être exécuté depuis le répertoire operator/"
    print_error "Fichiers/répertoires requis: build.gradle.kts, kubernetes/"
    exit 1
fi

main "$@"
