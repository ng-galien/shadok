#!/bin/bash

# Script de test pour les composants avancés de kind
# Usage: ./test-kind-config.sh [cluster-name]

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

# Test de cert-manager
test_cert_manager() {
    log_info "🔐 === Test de cert-manager ==="
    
    # Vérifier que cert-manager est installé
    if ! kubectl get namespace cert-manager --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_error "❌ Namespace cert-manager non trouvé"
        return 1
    fi
    
    # Vérifier que les pods sont en marche
    local ready_pods=$(kubectl get pods -n cert-manager --context "kind-${CLUSTER_NAME}" \
        --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ready_pods" -ge 3 ]; then
        log_success "✅ cert-manager opérationnel ($ready_pods pods)"
    else
        log_warning "⚠️  cert-manager partiellement opérationnel ($ready_pods pods)"
    fi
    
    # Tester la création d'un certificat
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert-temp
  namespace: default
spec:
  secretName: test-cert-temp-secret
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - temp-test.local
EOF
    
    # Attendre un peu et vérifier
    sleep 10
    if kubectl get certificate test-cert-temp --context "kind-${CLUSTER_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        log_success "🔒 Création de certificat fonctionnelle"
    else
        log_warning "⚠️  Création de certificat en cours..."
    fi
    
    # Nettoyer
    kubectl delete certificate test-cert-temp --context "kind-${CLUSTER_NAME}" &> /dev/null || true
    kubectl delete secret test-cert-temp-secret --context "kind-${CLUSTER_NAME}" &> /dev/null || true
    
    return 0
}

# Test d'ingress-nginx avec snippets
test_ingress_nginx() {
    log_info "🌐 === Test d'ingress-nginx avec snippets ==="
    
    # Vérifier que ingress-nginx est installé
    if ! kubectl get namespace ingress-nginx --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_error "❌ Namespace ingress-nginx non trouvé"
        return 1
    fi
    
    # Vérifier que les pods sont en marche
    local ready_pods=$(kubectl get pods -n ingress-nginx --context "kind-${CLUSTER_NAME}" \
        --selector=app.kubernetes.io/component=controller \
        --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ready_pods" -gt 0 ]; then
        log_success "✅ ingress-nginx opérationnel ($ready_pods pods)"
    else
        log_error "❌ ingress-nginx non opérationnel"
        return 1
    fi
    
    # Vérifier que les snippets sont activés
    local controller_config=$(kubectl get configmap ingress-nginx-controller -n ingress-nginx --context "kind-${CLUSTER_NAME}" -o jsonpath='{.data}' 2>/dev/null || echo "")
    
    if echo "$controller_config" | grep -q "allow-snippet-annotations"; then
        log_success "🔧 Snippets activés dans la configuration"
    else
        log_warning "⚠️  Configuration des snippets non détectée"
    fi
    
    # Créer un ingress de test avec snippet
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-service-temp
  namespace: default
spec:
  selector:
    app: curl-test
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress-temp
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Test-Snippet "Hello from snippet" always;
spec:
  ingressClassName: nginx
  rules:
  - host: test-snippet.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service-temp
            port:
              number: 80
EOF
    
    sleep 5
    
    # Tester l'ingress
    if kubectl get ingress test-ingress-temp --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_success "📝 Ingress avec snippet créé"
    else
        log_warning "⚠️  Échec de création de l'ingress avec snippet"
    fi
    
    # Nettoyer
    kubectl delete ingress test-ingress-temp --context "kind-${CLUSTER_NAME}" &> /dev/null || true
    kubectl delete service test-service-temp --context "kind-${CLUSTER_NAME}" &> /dev/null || true
    
    return 0
}

# Test du Kubernetes Dashboard
test_dashboard() {
    log_info "📊 === Test du Kubernetes Dashboard ==="
    
    # Vérifier que le dashboard est installé
    if ! kubectl get namespace kubernetes-dashboard --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_error "❌ Namespace kubernetes-dashboard non trouvé"
        return 1
    fi
    
    # Vérifier que les pods sont en marche
    local ready_pods=$(kubectl get pods -n kubernetes-dashboard --context "kind-${CLUSTER_NAME}" \
        --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$ready_pods" -gt 0 ]; then
        log_success "✅ Kubernetes Dashboard opérationnel ($ready_pods pods)"
    else
        log_error "❌ Kubernetes Dashboard non opérationnel"
        return 1
    fi
    
    # Vérifier l'ingress du dashboard
    if kubectl get ingress kubernetes-dashboard -n kubernetes-dashboard --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_success "🌐 Ingress dashboard configuré"
        
        # Vérifier l'annotation du snippet
        local snippet=$(kubectl get ingress kubernetes-dashboard -n kubernetes-dashboard --context "kind-${CLUSTER_NAME}" \
            -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/configuration-snippet}' 2>/dev/null || echo "")
        
        if echo "$snippet" | grep -q "Authorization"; then
            log_success "🔐 Snippet d'auto-login configuré"
        else
            log_warning "⚠️  Snippet d'auto-login non détecté"
        fi
    else
        log_warning "⚠️  Ingress dashboard non trouvé"
    fi
    
    # Vérifier le token d'accès
    if kubectl get secret dashboard-admin-token -n kubernetes-dashboard --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_success "🎫 Token d'accès admin créé"
    else
        log_warning "⚠️  Token d'accès admin non trouvé"
    fi
    
    return 0
}

# Test du pod curl
test_curl_pod() {
    log_info "🧪 === Test du pod curl ==="
    
    # Vérifier que le pod curl existe et est prêt
    if kubectl get pod curl-test --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        local pod_status=$(kubectl get pod curl-test --context "kind-${CLUSTER_NAME}" -o jsonpath='{.status.phase}')
        
        if [ "$pod_status" = "Running" ]; then
            log_success "✅ Pod curl-test opérationnel"
            
            # Tester une requête interne
            if kubectl exec curl-test --context "kind-${CLUSTER_NAME}" -- curl -s -o /dev/null -w "%{http_code}" \
                http://kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local 2>/dev/null | grep -q "200\|403\|404"; then
                log_success "🌐 Pod curl peut accéder aux services internes"
            else
                log_warning "⚠️  Pod curl ne peut pas accéder aux services internes"
            fi
            
            # Tester l'accès externe (DNS)
            if kubectl exec curl-test --context "kind-${CLUSTER_NAME}" -- curl -s -o /dev/null -w "%{http_code}" \
                https://httpbin.org/status/200 2>/dev/null | grep -q "200"; then
                log_success "🌍 Pod curl a accès à Internet"
            else
                log_warning "⚠️  Pod curl n'a pas accès à Internet"
            fi
            
        else
            log_error "❌ Pod curl-test non opérationnel (statut: $pod_status)"
            return 1
        fi
    else
        log_error "❌ Pod curl-test non trouvé"
        return 1
    fi
    
    return 0
}

# Test des certificats
test_certificates() {
    log_info "🔒 === Test des certificats ==="
    
    # Vérifier le ClusterIssuer
    if kubectl get clusterissuer selfsigned-issuer --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_success "✅ ClusterIssuer selfsigned-issuer configuré"
    else
        log_error "❌ ClusterIssuer selfsigned-issuer non trouvé"
        return 1
    fi
    
    # Vérifier le certificat de test
    if kubectl get certificate test-certificate --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        local cert_status=$(kubectl get certificate test-certificate --context "kind-${CLUSTER_NAME}" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$cert_status" = "True" ]; then
            log_success "🎫 Certificat de test valide et prêt"
        else
            log_warning "⚠️  Certificat de test en cours de création (statut: $cert_status)"
        fi
    else
        log_warning "⚠️  Certificat de test non trouvé"
    fi
    
    return 0
}

# Test de connectivité complète
test_connectivity() {
    log_info "🔗 === Test de connectivité complète ==="
    
    # Test depuis le pod curl vers le dashboard via l'ingress interne
    log_info "🧪 Test d'accès au dashboard via ingress..."
    
    # Ajouter une entrée temporaire dans /etc/hosts du pod curl
    kubectl exec curl-test --context "kind-${CLUSTER_NAME}" -- sh -c "echo '127.0.0.1 dashboard.local' >> /etc/hosts" 2>/dev/null || true
    
    # Test d'accès au dashboard (peut échouer si pas de /etc/hosts configuré sur l'hôte)
    local response=$(kubectl exec curl-test --context "kind-${CLUSTER_NAME}" -- \
        curl -s -o /dev/null -w "%{http_code}" http://dashboard.local 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ] || [ "$response" = "403" ] || [ "$response" = "404" ]; then
        log_success "🎯 Accès au dashboard via ingress fonctionnel (HTTP $response)"
    else
        log_warning "⚠️  Accès au dashboard via ingress non fonctionnel (HTTP $response)"
        log_info "   Ajoutez '127.0.0.1 dashboard.local' à /etc/hosts de l'hôte"
    fi
    
    return 0
}

# Afficher le résumé des tests
show_test_summary() {
    local cert_manager_ok=$1
    local ingress_ok=$2
    local dashboard_ok=$3
    local curl_ok=$4
    local certificates_ok=$5
    
    log_info "📊 === Résumé des tests de configuration ==="
    [ "$cert_manager_ok" -eq 0 ] && log_success "✅ cert-manager" || log_error "❌ cert-manager"
    [ "$ingress_ok" -eq 0 ] && log_success "✅ ingress-nginx (avec snippets)" || log_error "❌ ingress-nginx"
    [ "$dashboard_ok" -eq 0 ] && log_success "✅ Kubernetes Dashboard" || log_error "❌ Kubernetes Dashboard"
    [ "$curl_ok" -eq 0 ] && log_success "✅ Pod curl-test" || log_error "❌ Pod curl-test"
    [ "$certificates_ok" -eq 0 ] && log_success "✅ Certificats" || log_error "❌ Certificats"
    
    echo ""
    if [ "$cert_manager_ok" -eq 0 ] && [ "$ingress_ok" -eq 0 ] && [ "$dashboard_ok" -eq 0 ] && [ "$curl_ok" -eq 0 ] && [ "$certificates_ok" -eq 0 ]; then
        log_success "🎉 Tous les composants avancés sont opérationnels !"
        echo "   ✨ Le cluster kind est complètement configuré et prêt à l'emploi."
        echo ""
        log_info "🌐 Accès disponibles:"
        echo "   - Dashboard: http://dashboard.local"
        echo "   - Tests: kubectl exec -it curl-test -- sh"
        echo ""
        log_info "🔧 Configuration /etc/hosts requise:"
        echo "   echo '127.0.0.1 dashboard.local test.local' | sudo tee -a /etc/hosts"
    else
        log_error "💥 Certains composants ont des problèmes"
        echo "   🔍 Vérifiez les logs ci-dessus pour diagnostiquer."
        echo "   🔧 Relancez la configuration: ./kind-config.sh ${CLUSTER_NAME}"
    fi
}

# Fonction principale
main() {
    log_info "🧪 === Tests de configuration avancée kind '${CLUSTER_NAME}' ==="
    echo ""
    
    # Vérifier si le cluster existe
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_error "❌ Cluster kind '${CLUSTER_NAME}' non trouvé"
        echo "   🚀 Créez le cluster avec ./start-kind.sh"
        exit 1
    fi
    
    local cert_manager_result=1
    local ingress_result=1
    local dashboard_result=1
    local curl_result=1
    local certificates_result=1
    
    # Exécuter les tests
    test_cert_manager && cert_manager_result=0
    echo ""
    
    test_ingress_nginx && ingress_result=0
    echo ""
    
    test_dashboard && dashboard_result=0
    echo ""
    
    test_curl_pod && curl_result=0
    echo ""
    
    test_certificates && certificates_result=0
    echo ""
    
    test_connectivity
    echo ""
    
    # Afficher le résumé
    show_test_summary $cert_manager_result $ingress_result $dashboard_result $curl_result $certificates_result
    
    # Code de sortie basé sur les résultats
    if [ "$cert_manager_result" -eq 0 ] && [ "$ingress_result" -eq 0 ] && [ "$dashboard_result" -eq 0 ] && [ "$curl_result" -eq 0 ] && [ "$certificates_result" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Exécuter le script principal
main "$@"
