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

# Vérifier ingress-nginx et s'assurer que les snippets sont activés
verify_ingress_nginx() {
    log_info "🌐 Vérification d'ingress-nginx..."
    
    # Vérifier si ingress-nginx est installé et opérationnel
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_error "❌ Namespace ingress-nginx non trouvé"
        log_error "   Assurez-vous que start-kind.sh a été exécuté avec succès"
        exit 1
    fi
    
    if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers | grep -q "Running"; then
        log_error "❌ Contrôleur ingress-nginx non opérationnel"
        log_error "   Assurez-vous que start-kind.sh a été exécuté avec succès"
        exit 1
    fi
    
    # Vérifier que les snippets sont activés
    if kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.allow-snippet-annotations}' | grep -q "true"; then
        log_success "✅ ingress-nginx opérationnel avec snippets activés"
    else
        log_warning "⚠️  Les snippets ne semblent pas activés dans ingress-nginx"
    fi
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
    
    # Créer l'ingress avec injection du token et HTTPS
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    cert-manager.io/cluster-issuer: "selfsigned-issuer"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      # Auto-login avec le token JWT
      access_by_lua_block {
        local token = "${dashboard_token}"
        ngx.header["Authorization"] = "Bearer " .. token
      }
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - dashboard.127.0.0.1.nip.io
    secretName: dashboard-tls
  rules:
  - host: dashboard.127.0.0.1.nip.io
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
    
    log_success "📈 Kubernetes Dashboard installé avec auto-login et HTTPS"
    log_info "🌐 Accès: https://dashboard.127.0.0.1.nip.io"
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
  - dashboard.127.0.0.1.nip.io
  - shadok.127.0.0.1.nip.io
  - "*.127.0.0.1.nip.io"
  - "*.local"
EOF
    
    log_success "🔒 Certificat de test créé"
}

# Créer un serveur nginx de test avec ingress
create_test_nginx_server() {
    log_info "🌐 Création d'un serveur nginx de test..."
    
    # Créer le namespace pour les tests
    kubectl create namespace test-nginx --dry-run=client -o yaml | kubectl apply -f -
    
    # Déployer nginx avec une page personnalisée
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: test-nginx
  labels:
    app: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /usr/share/nginx/html
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-test-content
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-test-content
  namespace: test-nginx
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>🎪 Shadok Test Server</title>
        <style>
            body { 
                font-family: Arial, sans-serif; 
                background: linear-gradient(45deg, #667eea 0%, #764ba2 100%);
                color: white;
                text-align: center;
                padding: 50px;
                margin: 0;
            }
            .container {
                background: rgba(255,255,255,0.1);
                padding: 30px;
                border-radius: 15px;
                backdrop-filter: blur(10px);
                max-width: 600px;
                margin: 0 auto;
            }
            h1 { font-size: 3em; margin-bottom: 20px; }
            .emoji { font-size: 4em; }
            .info { background: rgba(0,0,0,0.3); padding: 15px; border-radius: 10px; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="emoji">🎪</div>
            <h1>Shadok Kind Cluster</h1>
            <p>Serveur nginx de test déployé avec succès !</p>
            <div class="info">
                <strong>Cluster:</strong> kind-shadok-dev<br>
                <strong>Namespace:</strong> test-nginx<br>
                <strong>Ingress:</strong> shadok.127.0.0.1.nip.io<br>
                <strong>Status:</strong> ✅ Opérationnel
            </div>
            <p>🚀 Votre environnement de développement Kubernetes est prêt !</p>
        </div>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: test-nginx
  labels:
    app: nginx-test
spec:
  selector:
    app: nginx-test
  ports:
  - port: 80
    targetPort: 80
    name: http
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test
  namespace: test-nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "selfsigned-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - shadok.127.0.0.1.nip.io
    secretName: nginx-test-tls
  rules:
  - host: shadok.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-test
            port:
              number: 80
EOF
    
    # Attendre que le déploiement soit prêt
    log_info "⏳ Attente que nginx soit prêt..."
    kubectl wait --for=condition=available deployment/nginx-test -n test-nginx --timeout=60s
    
    log_success "🌐 Serveur nginx de test déployé avec ingress"
    log_info "🔗 Accès: https://shadok.127.0.0.1.nip.io"
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
    echo "  - 🌐 Serveur nginx de test (avec ingress)"
    echo ""
    log_info "🌐 Services disponibles:"
    echo "  - Dashboard: https://dashboard.127.0.0.1.nip.io"
    echo "  - Test nginx: https://shadok.127.0.0.1.nip.io"
    echo "  - Ingress: http://localhost (port 80)"
    echo "  - Ingress HTTPS: https://localhost (port 443)"
    echo ""
    log_info "📋 Commandes utiles:"
    echo "  - kubectl get pods -A"
    echo "  - kubectl exec -it curl-test -- curl -H \"Host: shadok.127.0.0.1.nip.io\" https://ingress-nginx-controller.ingress-nginx.svc.cluster.local"
    echo "  - kubectl exec -it curl-test -- curl -k https://dashboard.127.0.0.1.nip.io"
    echo "  - kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller"
    echo "  - kubectl get certificates"
    echo ""
    log_info "🌐 Accès direct sans configuration:"
    echo "  - Dashboard: https://dashboard.127.0.0.1.nip.io"
    echo "  - Test nginx: https://shadok.127.0.0.1.nip.io"
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
    
    # Test du serveur nginx de test
    if kubectl get pods -n test-nginx | grep -q "Running"; then
        log_success "✅ Serveur nginx de test opérationnel"
        
        # Test de l'accès direct au service nginx
        log_info "🌐 Test de l'accès au service nginx..."
        if kubectl exec curl-test -- curl -s http://nginx-test.test-nginx.svc.cluster.local 2>/dev/null | grep -q "Shadok"; then
            log_success "✅ Accès au serveur nginx via service réussi"
        else
            log_warning "⚠️  Impossible d'accéder au serveur nginx via service"
        fi
    else
        log_warning "⚠️  Serveur nginx de test non opérationnel"
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
    
    verify_ingress_nginx
    echo ""
    
    install_dashboard
    echo ""
    
    create_curl_pod
    echo ""
    
    create_test_certificate
    echo ""
    
    create_test_nginx_server
    echo ""
    
    test_configuration
    echo ""
    
    show_config_info
}

# Exécuter le script principal
main "$@"
