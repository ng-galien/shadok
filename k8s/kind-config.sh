#!/bin/bash

# Script de configuration avancée pour kind
# Déploie cert-manager, ingress-nginx avec snippets, dashboard et pod curl
# Usage: ./kind-config.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
DASHBOARD_VERSION="v2.7.0"

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
    
    if ! command -v kubectl &> /dev/null; then
        log_error "❌ kubectl n'est pas installé"
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        log_error "❌ helm n'est pas installé. Installez-le avec: brew install helm"
        exit 1
    fi
    
    # Vérifier la connexion au cluster
    if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_error "❌ Impossible de se connecter au cluster kind-${CLUSTER_NAME}"
        log_error "   Assurez-vous que le cluster est démarré avec ./start-kind.sh"
        exit 1
    fi
    
    log_success "✅ Prérequis vérifiés"
}

# Ajouter les repositories Helm
add_helm_repos() {
    log_info "📦 Ajout des repositories Helm..."
    
    # Cert-manager
    helm repo add jetstack https://charts.jetstack.io --force-update
    
    # Ingress-nginx
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
    
    # Kubernetes Dashboard
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ --force-update
    
    # Mettre à jour les repos
    helm repo update
    
    log_success "📚 Repositories Helm ajoutés et mis à jour"
}

# Installer cert-manager
install_cert_manager() {
    log_info "🔐 Installation de cert-manager..."
    
    # Créer le namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Installer cert-manager avec Helm
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.2 \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait --timeout=300s
    
    # Attendre que cert-manager soit prêt
    log_info "⏳ Attente que cert-manager soit prêt..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager \
        -n cert-manager --timeout=300s
    
    log_success "🔒 cert-manager installé et opérationnel"
}

# Installer ingress-nginx avec snippets activés
install_ingress_nginx() {
    log_info "🌐 Installation d'ingress-nginx avec snippets..."
    
    # Créer le namespace
    kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
    
    # Créer les valeurs pour activer les snippets
    cat > /tmp/ingress-nginx-values.yaml <<EOF
controller:
  allowSnippetAnnotations: true
  config:
    allow-snippet-annotations: "true"
    enable-real-ip: "true"
    use-forwarded-headers: "true"
  extraArgs:
    enable-ssl-passthrough: true
  service:
    type: NodePort
  nodeSelector:
    ingress-ready: "true"
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Equal
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Equal
      effect: NoSchedule
  publishService:
    enabled: false
  extraEnvs:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
EOF
    
    # Installer ingress-nginx avec Helm
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --values /tmp/ingress-nginx-values.yaml \
        --wait --timeout=300s
    
    # Nettoyer le fichier temporaire
    rm -f /tmp/ingress-nginx-values.yaml
    
    # Attendre que l'ingress controller soit prêt
    log_info "⏳ Attente que l'ingress controller soit prêt..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller \
        -n ingress-nginx --timeout=300s
    
    log_success "🚀 ingress-nginx installé avec snippets activés"
}

# Installer le Kubernetes Dashboard
install_dashboard() {
    log_info "📊 Installation du Kubernetes Dashboard..."
    
    # Créer le namespace
    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
    
    # Installer le dashboard avec Helm
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --set app.ingress.enabled=false \
        --set nginx.enabled=false \
        --set cert-manager.enabled=false \
        --set app.settings.global.defaultNamespace=kubernetes-dashboard \
        --wait --timeout=300s
    
    # Créer un ServiceAccount pour l'accès admin
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: dashboard-admin
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: dashboard-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: dashboard-admin
type: kubernetes.io/service-account-token
EOF
    
    # Attendre que le token soit créé
    sleep 5
    
    # Récupérer le token JWT
    local dashboard_token=$(kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d)
    
    # Créer l'ingress avec injection du token
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      # Auto-login avec le token JWT
      access_by_lua_block {
        local token = "${dashboard_token}"
        ngx.header["Authorization"] = "Bearer " .. token
      }
spec:
  ingressClassName: nginx
  rules:
  - host: dashboard.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard-kong-proxy
            port:
              number: 443
EOF
    
    log_success "📈 Kubernetes Dashboard installé avec auto-login"
    log_info "🌐 Accès: http://dashboard.local (ajoutez à /etc/hosts: 127.0.0.1 dashboard.local)"
}

# Créer un pod curl pour les tests
create_curl_pod() {
    log_info "🔧 Création du pod curl pour les tests..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: curl-test
  namespace: default
  labels:
    app: curl-test
    purpose: testing
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ['sleep', '86400']  # 24 heures
    resources:
      requests:
        memory: "32Mi"
        cpu: "50m"
      limits:
        memory: "64Mi"
        cpu: "100m"
    env:
    - name: TERM
      value: xterm-256color
  restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  name: curl-test
  namespace: default
  labels:
    app: curl-test
spec:
  selector:
    app: curl-test
  ports:
  - port: 80
    targetPort: 8080
    name: http
EOF
    
    # Attendre que le pod soit prêt
    log_info "⏳ Attente que le pod curl soit prêt..."
    kubectl wait --for=condition=ready pod/curl-test --timeout=60s
    
    log_success "🧪 Pod curl-test créé et prêt pour les tests"
}

# Créer un certificat auto-signé pour les tests
create_test_certificate() {
    log_info "🔐 Création d'un certificat auto-signé pour les tests..."
    
    # Créer un ClusterIssuer pour les certificats auto-signés
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: default
spec:
  secretName: test-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - test.local
  - dashboard.local
  - "*.local"
EOF
    
    log_success "🔒 Certificat de test créé"
}

# Afficher les informations de configuration
show_config_info() {
    log_success "🎉 === Configuration kind terminée ! ==="
    echo ""
    log_info "🔧 Composants installés:"
    echo "  - 🔐 cert-manager (gestion des certificats)"
    echo "  - 🌐 ingress-nginx (avec snippets activés)"
    echo "  - 📊 Kubernetes Dashboard (avec auto-login)"
    echo "  - 🧪 Pod curl-test (pour les tests)"
    echo ""
    log_info "🌐 Services disponibles:"
    echo "  - Dashboard: http://dashboard.local"
    echo "  - Ingress: http://localhost (port 80)"
    echo "  - Ingress HTTPS: https://localhost (port 443)"
    echo ""
    log_info "📋 Commandes utiles:"
    echo "  - kubectl get pods -A"
    echo "  - kubectl exec -it curl-test -- curl http://dashboard.local"
    echo "  - kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller"
    echo "  - kubectl get certificates"
    echo ""
    log_info "🔧 Configuration /etc/hosts requise:"
    echo "  echo '127.0.0.1 dashboard.local test.local' | sudo tee -a /etc/hosts"
    echo ""
    
    # Afficher l'état des pods
    log_info "📊 État des pods système:"
    kubectl get pods -A -o wide | grep -E "(cert-manager|ingress-nginx|kubernetes-dashboard|curl-test)"
    echo ""
    
    # Afficher les ingress
    log_info "🌐 Ingress configurés:"
    kubectl get ingress -A
}

# Fonction de test rapide
test_configuration() {
    log_info "🧪 === Test rapide de la configuration ==="
    
    # Test du pod curl
    if kubectl exec curl-test -- curl -s -o /dev/null -w "%{http_code}" http://kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local 2>/dev/null | grep -q "200\|403"; then
        log_success "✅ Pod curl peut accéder aux services internes"
    else
        log_warning "⚠️  Pod curl ne peut pas accéder aux services internes"
    fi
    
    # Test de cert-manager
    if kubectl get pods -n cert-manager | grep -q "Running"; then
        log_success "✅ cert-manager opérationnel"
    else
        log_warning "⚠️  cert-manager non opérationnel"
    fi
    
    # Test d'ingress-nginx
    if kubectl get pods -n ingress-nginx | grep -q "Running"; then
        log_success "✅ ingress-nginx opérationnel"
    else
        log_warning "⚠️  ingress-nginx non opérationnel"
    fi
    
    # Test du dashboard
    if kubectl get pods -n kubernetes-dashboard | grep -q "Running"; then
        log_success "✅ Kubernetes Dashboard opérationnel"
    else
        log_warning "⚠️  Kubernetes Dashboard non opérationnel"
    fi
}

# Fonction principale
main() {
    log_info "🚀 === Configuration avancée du cluster kind '${CLUSTER_NAME}' ==="
    echo ""
    
    check_prerequisites
    add_helm_repos
    echo ""
    
    install_cert_manager
    echo ""
    
    install_ingress_nginx
    echo ""
    
    install_dashboard
    echo ""
    
    create_curl_pod
    echo ""
    
    create_test_certificate
    echo ""
    
    test_configuration
    echo ""
    
    show_config_info
}

# Exécuter le script principal
main "$@"
