#!/bin/bash

# 🔄 Quick Redeploy - Script de redéploiement rapide pour le développement
# ========================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="shadok"
REGISTRY="localhost:5001"
IMAGE_NAME="shadok/operator"
IMAGE_TAG="latest"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

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

quick_rebuild() {
    print_step "Reconstruction rapide de l'image..."

    # Build Gradle
    ./gradlew build -x test || {
        print_error "Échec du build Gradle"
        return 1
    }

    # Build Docker
    docker build -f Dockerfile.gradle -t "$FULL_IMAGE" . || {
        print_error "Échec du build Docker"
        return 1
    }

    # Push vers le registre local
    docker push "$FULL_IMAGE" || {
        print_error "Échec du push"
        return 1
    }

    print_success "Image reconstruite et poussée"
}

restart_operator() {
    print_step "Redémarrage de l'opérateur..."

    # Redémarrer le déploiement
    kubectl rollout restart deployment/shadok-operator -n "$NAMESPACE" || {
        print_error "Échec du redémarrage"
        return 1
    }

    # Attendre que le rollout soit terminé
    print_step "Attente du redémarrage..."
    kubectl rollout status deployment/shadok-operator -n "$NAMESPACE" --timeout=60s || {
        print_error "Timeout du redémarrage"
        return 1
    }

    print_success "Opérateur redémarré"
}

show_status() {
    print_step "État de l'opérateur..."

    echo ""
    echo "📋 Pods:"
    kubectl get pods -n "$NAMESPACE" -l app=shadok-operator

    echo ""
    echo "📋 Logs récents:"
    kubectl logs -n "$NAMESPACE" -l app=shadok-operator --tail=10 || {
        print_warning "Pas de logs disponibles"
    }
}

test_health() {
    print_step "Test de santé..."

    local pod=$(kubectl get pods -n "$NAMESPACE" -l app=shadok-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        print_error "Aucun pod trouvé"
        return 1
    fi

    # Test des endpoints
    if kubectl exec -n "$NAMESPACE" "$pod" -- curl -f http://localhost:8080/q/health/ready > /dev/null 2>&1; then
        print_success "Endpoint ready accessible"
    else
        print_error "Endpoint ready inaccessible"
        return 1
    fi

    return 0
}

show_help() {
    echo "🔄 Quick Redeploy - Redéploiement rapide pour le développement"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commandes:"
    echo "  rebuild    Reconstruire uniquement l'image"
    echo "  restart    Redémarrer uniquement l'opérateur"
    echo "  full       Reconstruire + redémarrer (défaut)"
    echo "  status     Afficher l'état"
    echo "  logs       Afficher les logs"
    echo "  test       Tester la santé"
    echo "  help       Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0           # Reconstruction + redémarrage"
    echo "  $0 rebuild   # Reconstruction seulement"
    echo "  $0 restart   # Redémarrage seulement"
    echo "  $0 status    # État actuel"
    echo ""
}

case "${1:-full}" in
    rebuild)
        echo "🔄 Reconstruction de l'image..."
        quick_rebuild
        print_success "Reconstruction terminée. Utilisez 'restart' pour redémarrer."
        ;;
    restart)
        echo "🔄 Redémarrage de l'opérateur..."
        restart_operator
        show_status
        ;;
    full)
        echo "🔄 Reconstruction et redéploiement complets..."
        quick_rebuild
        restart_operator
        show_status
        test_health
        print_success "Redéploiement terminé !"
        ;;
    status)
        show_status
        ;;
    logs)
        echo "📋 Logs de l'opérateur:"
        kubectl logs -n "$NAMESPACE" -l app=shadok-operator -f
        ;;
    test)
        test_health
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
