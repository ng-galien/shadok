#!/bin/bash

# Script de déploiement Quarkus vers Kubernetes (Kind)
# Ce script automatise le processus de construction, chargement d'image et déploiement

set -e

echo "🚀 Déploiement de quarkus-hello vers Kind..."

# Configuration
CLUSTER_NAME="shadok-dev"
NAMESPACE="shadok"
IMAGE_NAME="shadok-pods/quarkus-hello:latest"
REGISTRY_IMAGE_NAME="localhost:5001/shadok-pods/quarkus-hello:latest"
APP_NAME="quarkus-hello"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Vérifier que Kind est installé
if ! command -v kind &> /dev/null; then
    log_error "Kind n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

# Vérifier que kubectl est installé
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl n'est pas installé. Veuillez l'installer d'abord."
    exit 1
fi

# Vérifier que le cluster Kind existe
if ! kind get clusters | grep -q "shadok-dev"; then
    log_error "Le cluster Kind 'shadok-dev' n'existe pas. Veuillez le créer d'abord."
    exit 1
fi

# Vérifier que la registry locale est en marche
if ! docker ps | grep -q "shadok-registry"; then
    log_error "La registry locale 'shadok-registry' n'est pas en marche. Lancez ./start-kind.sh d'abord."
    exit 1
fi

# Vérifier que le contexte kubectl est correct
CURRENT_CONTEXT=$(kubectl config current-context)
if [[ "$CURRENT_CONTEXT" != "kind-shadok-dev" ]]; then
    log_warning "Le contexte kubectl actuel est '$CURRENT_CONTEXT'. Changement vers 'kind-shadok-dev'..."
    kubectl config use-context kind-shadok-dev
fi

# Étape 1: Construire l'application et l'image
log_info "Construction de l'application Quarkus..."
./gradlew build -Dquarkus.profile=kind

if [ $? -eq 0 ]; then
    log_success "Application construite avec succès"
else
    log_error "Échec de la construction de l'application"
    exit 1
fi

# Étape 2: Pousser l'image vers la registry locale
log_info "Tag et push de l'image vers la registry locale..."
docker tag $IMAGE_NAME $REGISTRY_IMAGE_NAME
docker push $REGISTRY_IMAGE_NAME

if [ $? -eq 0 ]; then
    log_success "Image poussée vers la registry locale avec succès"
else
    log_error "Échec du push de l'image vers la registry locale"
    exit 1
fi

# Étape 3: Créer le namespace s'il n'existe pas
log_info "Vérification du namespace '$NAMESPACE'..."
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    log_info "Création du namespace '$NAMESPACE'..."
    kubectl create namespace $NAMESPACE
    log_success "Namespace '$NAMESPACE' créé"
else
    log_info "Le namespace '$NAMESPACE' existe déjà"
fi

# Étape 4: Supprimer le déploiement existant s'il existe
log_info "Vérification du déploiement existant..."
if kubectl get deployment $APP_NAME -n $NAMESPACE &> /dev/null; then
    log_warning "Suppression du déploiement existant..."
    kubectl delete deployment $APP_NAME -n $NAMESPACE
    kubectl delete service $APP_NAME -n $NAMESPACE 2>/dev/null || true
    kubectl delete ingress $APP_NAME -n $NAMESPACE 2>/dev/null || true
    log_success "Déploiement existant supprimé"
fi

# Étape 5: Déployer l'application
log_info "Déploiement de l'application..."
kubectl apply -f build/kubernetes/kind.yml

if [ $? -eq 0 ]; then
    log_success "Application déployée avec succès"
else
    log_error "Échec du déploiement de l'application"
    exit 1
fi

# Étape 6: Attendre que le déploiement soit prêt
log_info "Attente que le déploiement soit prêt..."
kubectl wait --for=condition=available --timeout=300s deployment/$APP_NAME -n $NAMESPACE

if [ $? -eq 0 ]; then
    log_success "Déploiement prêt !"
else
    log_warning "Le déploiement prend plus de temps que prévu..."
fi

# Étape 7: Afficher l'état du déploiement
log_info "État du déploiement :"
kubectl get pods,services,ingress -n $NAMESPACE

# Étape 8: Afficher les informations de connexion
log_success "Déploiement terminé !"
echo ""
log_info "L'application est accessible via :"
echo "  - HTTPS: https://quarkus-hello.127.0.0.1.nip.io"
echo "  - HTTP:  http://quarkus-hello.127.0.0.1.nip.io"
echo ""
log_info "Commandes utiles :"
echo "  - Logs: kubectl logs -f deployment/$APP_NAME -n $NAMESPACE"
echo "  - Port-forward: kubectl port-forward svc/$APP_NAME 8080:80 -n $NAMESPACE"
echo "  - Supprimer: kubectl delete -f build/kubernetes/kind.yml"
echo ""
log_info "Test des endpoints :"
echo "  ./test-endpoints.sh"
