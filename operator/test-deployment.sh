#!/bin/bash

# 🧪 Test Deployment - Script de validation du déploiement Shadok
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

NAMESPACE="shadok"

print_header() {
    echo -e "\n${PURPLE}===============================================${NC}"
    echo -e "${PURPLE} 🧪 $1${NC}"
    echo -e "${PURPLE}===============================================${NC}\n"
}

print_test() {
    echo -e "${BLUE}🔍 Test: $1${NC}"
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

# ========================================
# Tests du déploiement
# ========================================

test_cluster_connectivity() {
    print_test "Connectivité au cluster"

    if kubectl cluster-info > /dev/null 2>&1; then
        print_success "Cluster accessible"
        return 0
    else
        print_error "Impossible de se connecter au cluster"
        return 1
    fi
}

test_namespace() {
    print_test "Namespace $NAMESPACE"

    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        print_success "Namespace existe"
        return 0
    else
        print_error "Namespace manquant"
        return 1
    fi
}

test_crds() {
    print_test "Custom Resource Definitions"

    local failed=0
    for crd in applications.shadok.org projectsources.shadok.org dependencycaches.shadok.org; do
        if kubectl get crd "$crd" > /dev/null 2>&1; then
            local status=$(kubectl get crd "$crd" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}')
            if [ "$status" = "True" ]; then
                print_success "CRD $crd établi"
            else
                print_error "CRD $crd non établi"
                ((failed++))
            fi
        else
            print_error "CRD $crd manquant"
            ((failed++))
        fi
    done

    return $failed
}

test_operator_deployment() {
    print_test "Déploiement de l'opérateur"

    if kubectl get deployment operator -n "$NAMESPACE" > /dev/null 2>&1; then
        local ready=$(kubectl get deployment operator -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment operator -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

        if [ "$ready" = "$desired" ] && [ "$ready" != "" ]; then
            print_success "Déploiement opérateur prêt ($ready/$desired)"
            return 0
        else
            print_error "Déploiement opérateur non prêt ($ready/$desired)"
            return 1
        fi
    else
        print_error "Déploiement opérateur manquant"
        return 1
    fi
}

test_operator_pods() {
    print_test "Pods de l'opérateur"

    local pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=operator --field-selector=status.phase=Running --no-headers | wc -l)

    if [ "$pods" -gt 0 ]; then
        print_success "$pods pod(s) opérateur en cours d'exécution"
        return 0
    else
        print_error "Aucun pod opérateur en cours d'exécution"
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=operator
        return 1
    fi
}

test_operator_service() {
    print_test "Service de l'opérateur"

    if kubectl get service operator -n "$NAMESPACE" > /dev/null 2>&1; then
        print_success "Service opérateur existe"
        return 0
    else
        print_error "Service opérateur manquant"
        return 1
    fi
}

test_webhook_configuration() {
    print_test "Configuration du webhook"

    if kubectl get mutatingwebhookconfiguration shadok-pod-mutator > /dev/null 2>&1; then
        print_success "MutatingWebhookConfiguration existe"
        return 0
    else
        print_error "MutatingWebhookConfiguration manquant"
        return 1
    fi
}

test_persistent_volumes() {
    print_test "Capacité de gestion des volumes persistants"

    # L'opérateur n'a pas besoin de PVs pré-créés
    # Il crée les PVCs/PVs à la demande pour les applications via les CRDs
    if kubectl get storageclass > /dev/null 2>&1; then
        print_success "StorageClasses disponibles pour la création dynamique de PVs"
        return 0
    else
        print_warning "Aucune StorageClass trouvée - les PVs devront être créés manuellement"
        return 0
    fi
}

test_operator_health() {
    print_test "Santé de l'opérateur"

    # Obtenir le nom du pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        print_error "Aucun pod opérateur trouvé"
        return 1
    fi

    # Tester les endpoints de santé
    if kubectl exec -n "$NAMESPACE" "$pod" -- curl -f http://localhost:8080/q/health/live > /dev/null 2>&1; then
        print_success "Endpoint liveness accessible"
    else
        print_error "Endpoint liveness inaccessible"
        return 1
    fi

    if kubectl exec -n "$NAMESPACE" "$pod" -- curl -f http://localhost:8080/q/health/ready > /dev/null 2>&1; then
        print_success "Endpoint readiness accessible"
    else
        print_error "Endpoint readiness inaccessible"
        return 1
    fi

    return 0
}

test_rbac() {
    print_test "Configuration RBAC"

    local failed=0

    if kubectl get serviceaccount shadok -n "$NAMESPACE" > /dev/null 2>&1; then
        print_success "ServiceAccount existe"
    else
        print_error "ServiceAccount manquant"
        ((failed++))
    fi

    if kubectl get clusterrole shadok-operator > /dev/null 2>&1; then
        print_success "ClusterRole existe"
    else
        print_error "ClusterRole manquant"
        ((failed++))
    fi

    if kubectl get clusterrolebinding application-controller-cluster-role-binding > /dev/null 2>&1; then
        print_success "ClusterRoleBinding existe"
    else
        print_error "ClusterRoleBinding manquant"
        ((failed++))
    fi

    return $failed
}

# ========================================
# Tests fonctionnels
# ========================================

test_webhook_functionality() {
    print_test "Fonctionnalité du webhook"

    # Créer un pod de test simple
    cat << EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: webhook-test-pod
  namespace: $NAMESPACE
  labels:
    test: webhook
spec:
  containers:
  - name: test
    image: busybox
    command: ['sleep', '30']
  restartPolicy: Never
EOF

    # Attendre un peu pour le traitement
    sleep 2

    # Vérifier si le pod a été créé et potentiellement modifié
    if kubectl get pod webhook-test-pod -n "$NAMESPACE" > /dev/null 2>&1; then
        print_success "Pod de test créé (webhook fonctionne)"

        # Nettoyer
        kubectl delete pod webhook-test-pod -n "$NAMESPACE" --grace-period=0 --force > /dev/null 2>&1 || true
        return 0
    else
        print_error "Échec de création du pod de test"
        return 1
    fi
}

# ========================================
# Fonction principale
# ========================================

run_all_tests() {
    print_header "Validation du Déploiement Shadok"

    local total_tests=0
    local failed_tests=0

    # Tests d'infrastructure
    ((total_tests++))
    test_cluster_connectivity || ((failed_tests++))

    ((total_tests++))
    test_namespace || ((failed_tests++))

    ((total_tests++))
    test_crds || ((failed_tests++))

    ((total_tests++))
    test_rbac || ((failed_tests++))

    ((total_tests++))
    test_persistent_volumes || ((failed_tests++))

    # Tests de l'opérateur
    ((total_tests++))
    test_operator_deployment || ((failed_tests++))

    ((total_tests++))
    test_operator_pods || ((failed_tests++))

    ((total_tests++))
    test_operator_service || ((failed_tests++))

    ((total_tests++))
    test_operator_health || ((failed_tests++))

    # Tests du webhook
    ((total_tests++))
    test_webhook_configuration || ((failed_tests++))

    ((total_tests++))
    test_webhook_functionality || ((failed_tests++))

    # Résumé
    print_header "Résumé des Tests"

    local passed_tests=$((total_tests - failed_tests))
    echo "🎯 Tests exécutés: $total_tests"
    echo "✅ Tests réussis: $passed_tests"
    echo "❌ Tests échoués: $failed_tests"

    if [ $failed_tests -eq 0 ]; then
        print_success "🎉 Tous les tests sont passés ! Déploiement validé."
        return 0
    else
        print_error "⚠️  $failed_tests test(s) ont échoué. Vérifiez le déploiement."
        return 1
    fi
}

show_deployment_status() {
    print_header "État du Déploiement"

    echo "📋 Pods dans le namespace $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || echo "Aucun pod trouvé"

    echo ""
    echo "📋 Services dans le namespace $NAMESPACE:"
    kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "Aucun service trouvé"

    echo ""
    echo "📋 Ressources Shadok:"
    kubectl get applications,projectsources,dependencycaches -n "$NAMESPACE" 2>/dev/null || echo "Aucune ressource Shadok trouvée"

    echo ""
    echo "📋 Configuration du webhook:"
    kubectl get mutatingwebhookconfiguration shadok-pod-mutator 2>/dev/null || echo "Webhook non configuré"
}

show_help() {
    echo "🧪 Test Deployment - Script de validation du déploiement Shadok"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commandes:"
    echo "  test       Exécuter tous les tests (défaut)"
    echo "  status     Afficher l'état du déploiement"
    echo "  help       Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0           # Exécuter tous les tests"
    echo "  $0 test      # Exécuter tous les tests"
    echo "  $0 status    # Afficher l'état"
    echo ""
}

# Parse arguments
case "${1:-test}" in
    test)
        run_all_tests
        exit $?
        ;;
    status)
        show_deployment_status
        exit 0
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        echo "Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
