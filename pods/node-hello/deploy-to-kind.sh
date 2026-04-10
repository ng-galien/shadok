#!/bin/bash

# 🚀 Deploy Node Hello to Kind - Deployment Management
# ======================================================
#
# Script pour gérer le déploiement de l'application node-hello
# avec les ressources Shadok CRDs dans Kind
#
# Usage: ./deploy-to-kind.sh [action] [options]

set -e

# Configuration
CLUSTER_NAME="shadok-dev"
NAMESPACE="shadok"
REGISTRY="localhost:5001"
IMAGE_NAME="node-hello"
IMAGE_TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

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

# Vérifier les prérequis
check_prerequisites() {
    print_header "Vérification des Prérequis"

    for tool in kind kubectl docker node npm; do
        if ! command -v $tool > /dev/null 2>&1; then
            print_error "$tool n'est pas installé"
            exit 1
        fi
    done

    if ! docker info > /dev/null 2>&1; then
        print_error "Docker n'est pas en cours d'exécution"
        exit 1
    fi

    print_success "Tous les prérequis sont OK"
}

# Vérifier le cluster Kind
check_cluster() {
    print_header "Vérification du Cluster Kind"

    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        print_error "Cluster Kind '$CLUSTER_NAME' non trouvé"
        print_step "Démarrez d'abord l'opérateur avec: cd ../../operator && ./deploy-to-kind.sh"
        exit 1
    fi

    if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" > /dev/null 2>&1; then
        print_error "Impossible de se connecter au cluster"
        exit 1
    fi

    print_success "Cluster '$CLUSTER_NAME' accessible"
}

# Construire l'image
build_image() {
    print_header "Construction de l'Image"

    print_step "Installation des dépendances..."
    npm ci

    print_step "Build image Docker..."
    docker build -t "$FULL_IMAGE" .

    print_step "Push vers le registre local..."
    docker push "$FULL_IMAGE"

    print_success "Image $FULL_IMAGE construite et poussée"
}

# Déployer l'application avec CRDs
deploy_app() {
    print_header "Déploiement de l'Application"

    # S'assurer que les PVCs sont dans le bon namespace
    ensure_pvcs_namespace

    print_step "Application des ressources Shadok CRDs..."
    # kubectl apply -f k8s/shadok-resources.yml

    print_step "Attente que l'opérateur traite les ressources..."
    sleep 10

    # Vérifier que l'application est créée
    if kubectl get application node-hello-app -n "$NAMESPACE" > /dev/null 2>&1; then
        print_success "Ressources Shadok CRDs appliquées"
    else
        print_error "Échec de la création des ressources CRDs"
        return 1
    fi

    # Déployer l'application avec les manifests Kubernetes
    print_step "Déploiement de l'application avec les manifests Kubernetes..."
    kubectl apply -f k8s/deployment.yml -f k8s/service.yml -f k8s/ingress.yml

    print_step "Attente que le déploiement soit prêt..."
    kubectl wait --for=condition=available deployment/node-hello -n "$NAMESPACE" --timeout=120s

    print_success "Application déployée avec l'annotation Shadok"
}

# Désinstaller l'application
uninstall_app() {
    print_header "Désinstallation de l'Application"

    print_step "Suppression des ressources Shadok CRDs..."
    kubectl delete -f k8s/shadok-resources.yml --ignore-not-found=true

    print_step "Attente de la suppression des ressources..."
    sleep 5

    # Vérifier que les ressources sont supprimées
    local resources_deleted=true
    for app in node-hello-app test-node-app; do
        if kubectl get application $app -n "$NAMESPACE" > /dev/null 2>&1; then
            resources_deleted=false
            break
        fi
    done

    if [ "$resources_deleted" = true ]; then
        print_success "Ressources Shadok supprimées"
    else
        print_warning "Certaines ressources peuvent encore exister"
    fi

    # Nettoyer les déploiements restants
    print_step "Nettoyage des déploiements restants..."
    kubectl delete deployment node-hello -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete service node-hello -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete ingress node-hello -n "$NAMESPACE" --ignore-not-found=true

    print_success "Désinstallation terminée"
}

# Redémarrer le pod
restart_app() {
    print_header "Redémarrage de l'Application"

    # Vérifier que l'application existe
    if ! kubectl get deployment node-hello -n "$NAMESPACE" > /dev/null 2>&1; then
        print_error "Aucun déploiement 'node-hello' trouvé"
        print_step "Utilisez --install pour déployer l'application d'abord"
        return 1
    fi

    print_step "Redémarrage du déploiement..."
    kubectl rollout restart deployment/node-hello -n "$NAMESPACE"

    print_step "Attente du redémarrage..."
    kubectl rollout status deployment/node-hello -n "$NAMESPACE" --timeout=120s

    print_success "Application redémarrée"
}

# Installer les CRDs
install_crds() {
    print_header "Installation des CRDs Shadok"

    print_step "Application des ressources CRDs..."
    kubectl apply -f k8s/shadok-resources.yml

    print_step "Vérification des ressources créées..."

    # Lister les ressources créées
    echo ""
    echo "📋 Ressources créées :"
    kubectl get applications -n "$NAMESPACE" 2>/dev/null || echo "  Aucune Application"
    kubectl get projectsources -n "$NAMESPACE" 2>/dev/null || echo "  Aucune ProjectSource"
    kubectl get dependencycaches -n "$NAMESPACE" 2>/dev/null || echo "  Aucune DependencyCache"
    echo ""

    print_success "CRDs installées"
}

# Désinstaller les CRDs
uninstall_crds() {
    print_header "Désinstallation des CRDs Shadok"

    print_step "Suppression des ressources CRDs..."
    kubectl delete -f k8s/shadok-resources.yml --ignore-not-found=true

    print_step "Nettoyage des ressources restantes..."
    # Nettoyer les PVCs si elles existent
    kubectl delete pvc node-hello-source-pvc -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete pvc node-modules-cache-pvc -n "$NAMESPACE" --ignore-not-found=true

    print_success "CRDs désinstallées"
}

# S'assurer que les PVCs sont dans le bon namespace
ensure_pvcs_namespace() {
    print_header "Vérification des PVCs"

    # Vérifier si les PVCs existent dans le mauvais namespace (default)
    local wrong_pvcs=$(kubectl get pvc -n default -l app=shadok --no-headers 2>/dev/null | wc -l)
    if [ "$wrong_pvcs" -gt 0 ]; then
        print_warning "PVCs trouvées dans le namespace 'default', nettoyage nécessaire"

        # Supprimer les PVCs du namespace default
        print_step "Suppression des PVCs du namespace 'default'..."
        kubectl delete pvc -n default -l app=shadok --ignore-not-found=true

        # Nettoyer les PVs pour qu'ils redeviennent Available
        print_step "Nettoyage des PersistentVolumes..."
        for pv in $(kubectl get pv -l app=shadok --no-headers | awk '{print $1}'); do
            kubectl patch pv "$pv" --type merge -p '{"spec":{"claimRef":null}}'
        done

        print_success "Nettoyage terminé"
    fi

    # Créer le namespace shadok s'il n'existe pas
    print_step "Création du namespace 'shadok' si nécessaire..."
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Vérifier si les PVCs existent dans le bon namespace
    local correct_pvcs=$(kubectl get pvc -n "$NAMESPACE" -l app=shadok --no-headers 2>/dev/null | wc -l)
    if [ "$correct_pvcs" -eq 0 ]; then
        print_step "Création des PVCs dans le namespace '$NAMESPACE'..."

        # Créer les PVCs pour node-hello
        kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-node-hello-sources
  namespace: $NAMESPACE
  labels:
    app: shadok
    pod: node-hello
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
      pod: node-hello
      type: sources
EOF

        print_success "PVCs créées dans le namespace '$NAMESPACE'"
    else
        print_success "PVCs déjà présentes dans le namespace '$NAMESPACE'"
    fi
}

# Tester l'application
test_app() {
    print_header "Test de l'Application"

    # Utiliser directement l'URL nip.io
    local ingress_url="http://node-hello.127.0.0.1.nip.io"
    print_step "URL de test: $ingress_url"

    # Vérifier que l'ingress est prêt
    print_step "Vérification de l'ingress..."
    local ingress_ready=false
    for i in {1..10}; do
        local ingress_address=$(kubectl get ingress node-hello -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -z "$ingress_address" ]; then
            ingress_address=$(kubectl get ingress node-hello -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        fi
        if [ -n "$ingress_address" ]; then
            ingress_ready=true
            print_success "Ingress prêt avec l'adresse: $ingress_address"
            break
        fi
        sleep 2
    done

    if [ "$ingress_ready" = false ]; then
        print_warning "Ingress pas encore prêt, mais test direct avec nip.io"
    fi

    print_step "Attente que l'application soit prête..."
    sleep 5

    # Test de l'endpoint principal
    print_step "Test: curl $ingress_url/hello"
    local hello_response=$(curl -s "$ingress_url/hello" 2>/dev/null || echo "")
    if [ -n "$hello_response" ] && echo "$hello_response" | grep -q "Hello"; then
        print_success "✅ Endpoint /hello: $hello_response"
    else
        print_error "❌ Endpoint /hello inaccessible"
        return 1
    fi

    # Test de l'endpoint JSON
    print_step "Test: curl $ingress_url/hello/json"
    local json_response=$(curl -s "$ingress_url/hello/json" 2>/dev/null || echo "")
    if [ -n "$json_response" ] && echo "$json_response" | grep -q "message"; then
        print_success "✅ Endpoint /hello/json: $json_response"
    else
        print_warning "⚠️  Endpoint /hello/json inaccessible ou format inattendu"
    fi

    echo ""
    print_success "🎉 Application accessible via: $ingress_url"
}

# Afficher les informations de déploiement
show_status() {
    print_header "État du Déploiement"

    echo "🎯 Application: node-hello"
    echo "📦 Namespace: $NAMESPACE"
    echo "🏷️  Image: $FULL_IMAGE"
    echo ""

    # État des ressources CRDs
    echo "📋 Ressources Shadok CRDs:"
    kubectl get applications -n "$NAMESPACE" 2>/dev/null || echo "  Aucune Application"
    kubectl get projectsources -n "$NAMESPACE" 2>/dev/null || echo "  Aucune ProjectSource"
    kubectl get dependencycaches -n "$NAMESPACE" 2>/dev/null || echo "  Aucune DependencyCache"
    echo ""

    # État du déploiement
    echo "📋 Déploiement Kubernetes:"
    if kubectl get deployment node-hello -n "$NAMESPACE" > /dev/null 2>&1; then
        kubectl get deployment node-hello -n "$NAMESPACE"
        kubectl get pods -n "$NAMESPACE" -l app=node-hello
    else
        echo "  Aucun déploiement actif"
    fi
    echo ""

    # Ingress
    if kubectl get ingress node-hello -n "$NAMESPACE" > /dev/null 2>&1; then
        echo "🌐 Accès via Ingress:"
        echo "  http://node-hello.127.0.0.1.nip.io/hello"
        echo "  http://node-hello.127.0.0.1.nip.io/hello/json"
        echo "  https://node-hello.127.0.0.1.nip.io/hello (HTTPS)"
        echo ""
        echo "🧪 Tests:"
        echo "  curl http://node-hello.127.0.0.1.nip.io/hello"
        echo "  curl http://node-hello.127.0.0.1.nip.io/hello/json"
        echo "  curl -k https://node-hello.127.0.0.1.nip.io/hello"
    else
        echo "🌐 Aucun ingress configuré"
    fi
    echo ""
}

# Fonction principale
main() {
    local ACTION="install"  # Action par défaut
    local SKIP_BUILD=false
    local SKIP_TESTS=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                ACTION="install"
                shift
                ;;
            --uninstall)
                ACTION="uninstall"
                shift
                ;;
            --restart)
                ACTION="restart"
                shift
                ;;
            --install-crd)
                ACTION="install-crd"
                shift
                ;;
            --uninstall-crd)
                ACTION="uninstall-crd"
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --help)
                echo "Usage: $0 [action] [options]"
                echo ""
                echo "Actions (mutuellement exclusives):"
                echo "  --install        Construire et déployer l'application (défaut)"
                echo "  --uninstall      Supprimer le déploiement"
                echo "  --restart        Redémarrer le pod"
                echo "  --install-crd    Installer seulement les ressources CRDs"
                echo "  --uninstall-crd  Désinstaller seulement les ressources CRDs"
                echo ""
                echo "Options (pour --install seulement):"
                echo "  --skip-build     Ne pas reconstruire l'image"
                echo "  --skip-tests     Ignorer les tests"
                echo "  --help           Afficher cette aide"
                echo ""
                echo "Exemples:"
                echo "  $0                    # Installation complète (défaut)"
                echo "  $0 --install          # Installation complète explicite"
                echo "  $0 --install --skip-build  # Installation sans rebuild"
                echo "  $0 --uninstall        # Désinstallation"
                echo "  $0 --restart          # Redémarrage"
                echo "  $0 --install-crd      # Installation CRDs seulement"
                echo "  $0 --uninstall-crd    # Désinstallation CRDs seulement"
                exit 0
                ;;
            *)
                print_error "Option inconnue: $1"
                echo "Utilisez --help pour voir les options disponibles"
                exit 1
                ;;
        esac
    done

    # Header
    echo -e "${PURPLE}"
    echo "🚀 ======================================== 🚀"
    echo "   Deploy Node Hello to Kind"
    case $ACTION in
        "install")
            echo "   Action: Installation (Build + Deploy + Test)"
            ;;
        "uninstall")
            echo "   Action: Désinstallation"
            ;;
        "restart")
            echo "   Action: Redémarrage"
            ;;
        "install-crd")
            echo "   Action: Installation CRDs"
            ;;
        "uninstall-crd")
            echo "   Action: Désinstallation CRDs"
            ;;
    esac
    echo "========================================"
    echo -e "${NC}"

    # Vérifications communes
    check_prerequisites
    check_cluster

    # Exécution selon l'action
    case $ACTION in
        "install")
            if [ "$SKIP_BUILD" = false ]; then
                build_image
            fi
            deploy_app
            if [ "$SKIP_TESTS" = false ]; then
                test_app
            fi
            show_status
            print_success "🎉 Installation terminée avec succès !"
            ;;
        "uninstall")
            uninstall_app
            show_status
            print_success "🗑️  Désinstallation terminée !"
            ;;
        "restart")
            restart_app
            if [ "$SKIP_TESTS" = false ]; then
                test_app
            fi
            show_status
            print_success "🔄 Redémarrage terminé !"
            ;;
        "install-crd")
            install_crds
            show_status
            print_success "📦 Installation CRDs terminée !"
            ;;
        "uninstall-crd")
            uninstall_crds
            show_status
            print_success "🗑️  Désinstallation CRDs terminée !"
            ;;
        *)
            print_error "Action inconnue: $ACTION"
            exit 1
            ;;
    esac
}

# Vérifier qu'on est dans le bon répertoire
if [ ! -f "package.json" ] || [ ! -d "src" ]; then
    print_error "Ce script doit être exécuté depuis le répertoire pods/node-hello/"
    exit 1
fi

main "$@"
