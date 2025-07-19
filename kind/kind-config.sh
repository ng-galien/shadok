#!/bin/bash

# Advanced configuration script for kind
# Deploys cert-manager, ingress-nginx with snippets, dashboard and curl pod
# Usage: ./kind-config.sh [cluster-name]

set -euo pipefail

# Configuration
CLUSTER_NAME="${1:-shadok-dev}"
DASHBOARD_VERSION="v2.7.0"

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

    if ! command -v kubectl &> /dev/null; then
        log_error "❌ kubectl is not installed"
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "❌ helm is not installed. Install it with: brew install helm"
        exit 1
    fi

    # Check connection to the cluster
    if ! kubectl cluster-info --context "kind-${CLUSTER_NAME}" &> /dev/null; then
        log_error "❌ Unable to connect to cluster kind-${CLUSTER_NAME}"
        log_error "   Make sure the cluster is started with ./start-kind.sh"
        exit 1
    fi

    log_success "✅ Prerequisites verified"
}

# Add Helm repositories
add_helm_repos() {
    log_info "📦 Adding Helm repositories..."

    # Cert-manager
    helm repo add jetstack https://charts.jetstack.io --force-update

    # Ingress-nginx
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update

    # Kubernetes Dashboard
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ --force-update

    # Update repositories
    helm repo update

    log_success "📚 Helm repositories added and updated"
}

# Install cert-manager
install_cert_manager() {
    log_info "🔐 Installing cert-manager..."

    # Create the namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

    # Install cert-manager with Helm
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.2 \
        --set installCRDs=true \
        --set global.leaderElection.namespace=cert-manager \
        --wait --timeout=300s

    # Wait for cert-manager to be ready
    log_info "⏳ Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager \
        -n cert-manager --timeout=300s

    log_success "🔒 cert-manager installed and operational"
}

# Verify ingress-nginx and ensure snippets are enabled
verify_ingress_nginx() {
    log_info "🌐 Verifying ingress-nginx..."

    # Check if ingress-nginx is installed and operational
    if ! kubectl get namespace ingress-nginx &> /dev/null; then
        log_error "❌ Namespace ingress-nginx not found"
        log_error "   Make sure start-kind.sh has been executed successfully"
        exit 1
    fi

    if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers | grep -q "Running"; then
        log_error "❌ ingress-nginx controller not operational"
        log_error "   Make sure start-kind.sh has been executed successfully"
        exit 1
    fi

    # Check that snippets are enabled
    if kubectl get configmap ingress-nginx-controller -n ingress-nginx -o jsonpath='{.data.allow-snippet-annotations}' | grep -q "true"; then
        log_success "✅ ingress-nginx operational with snippets enabled"
    else
        log_warning "⚠️  Snippets do not appear to be enabled in ingress-nginx"
    fi
}

# Install the Kubernetes Dashboard
install_dashboard() {
    log_info "📊 Installing Kubernetes Dashboard..."

    # Create the namespace
    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

    # Install the dashboard with Helm
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --set app.ingress.enabled=false \
        --set nginx.enabled=false \
        --set cert-manager.enabled=false \
        --set app.settings.global.defaultNamespace=kubernetes-dashboard \
        --wait --timeout=300s

    # Create a ServiceAccount for admin access
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
EOF

    # Wait for the token to be created
    sleep 5

    # Generate a JWT token with the recommended method
    local dashboard_token=$(kubectl -n kubernetes-dashboard create token dashboard-admin)

    # Create the ingress with token injection and HTTPS
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
      proxy_set_header Authorization "Bearer ${dashboard_token}";
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

    # Wait for all dashboard deployments to be ready
    log_info "⏳ Waiting for all dashboard deployments to be operational..."
    kubectl wait --for=condition=available deployment -l app.kubernetes.io/part-of=kubernetes-dashboard \
        -n kubernetes-dashboard --timeout=120s

    log_success "📈 Kubernetes Dashboard installed with auto-login and HTTPS"
    log_info "🌐 Access: https://dashboard.127.0.0.1.nip.io"
}

# Create a curl pod for testing
create_curl_pod() {
    log_info "🔧 Creating curl pod for testing..."

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
    command: ['sleep', '86400']  # 24 hours
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

    # Wait for the pod to be ready
    log_info "⏳ Waiting for curl pod to be ready..."
    kubectl wait --for=condition=ready pod/curl-test --timeout=60s

    log_success "🧪 curl-test pod created and ready for testing"
}

# Create a self-signed certificate for testing
create_test_certificate() {
    log_info "🔐 Creating a self-signed certificate for testing..."

    # Create a ClusterIssuer for self-signed certificates
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

    log_success "🔒 Test certificate created"
}

# Create a test nginx server with ingress
create_test_nginx_server() {
    log_info "🌐 Creating a test nginx server..."

    # The shadok namespace already exists, no need to recreate it

    # Deploy nginx with a custom page
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: shadok
  labels:
    app: nginx-test
spec:
  replicas: 1
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
  namespace: shadok
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
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
            <p>Test nginx server deployed successfully!</p>
            <div class="info">
                <strong>Cluster:</strong> kind-shadok-dev<br>
                <strong>Namespace:</strong> shadok<br>
                <strong>Ingress:</strong> shadok.127.0.0.1.nip.io<br>
                <strong>Status:</strong> ✅ Operational
            </div>
            <p>🚀 Your Kubernetes development environment is ready!</p>
            <div class="info">
                <a href="https://dashboard.127.0.0.1.nip.io" style="color: white; text-decoration: underline;">📊 Access Kubernetes Dashboard</a>
            </div>
        </div>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: shadok
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
  namespace: shadok
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

    # Wait for the deployment to be ready
    log_info "⏳ Waiting for nginx to be ready..."
    kubectl wait --for=condition=available deployment/nginx-test -n shadok --timeout=60s

    log_success "🌐 Test nginx server deployed with ingress"
    log_info "🔗 Access: https://shadok.127.0.0.1.nip.io"
}

# Display configuration information
show_config_info() {
    log_success "🎉 === Kind configuration completed! ==="
    echo ""
    log_info "🔧 Installed components:"
    echo "  - 🔐 cert-manager (certificate management)"
    echo "  - 🌐 ingress-nginx (with snippets enabled)"
    echo "  - 📊 Kubernetes Dashboard (with auto-login)"
    echo "  - 🧪 curl-test pod (for testing)"
    echo "  - 🌐 Test nginx server (with ingress)"
    echo ""
    log_info "🌐 Available services:"
    echo "  - Dashboard: https://dashboard.127.0.0.1.nip.io"
    echo "  - Test nginx: https://shadok.127.0.0.1.nip.io"
    echo "  - Ingress: http://localhost (port 80)"
    echo "  - Ingress HTTPS: https://localhost (port 443)"
    echo ""
    log_info "📋 Useful commands:"
    echo "  - kubectl get pods -A"
    echo "  - kubectl exec -it curl-test -- curl -H \"Host: shadok.127.0.0.1.nip.io\" https://ingress-nginx-controller.ingress-nginx.svc.cluster.local"
    echo "  - kubectl exec -it curl-test -- curl -k https://dashboard.127.0.0.1.nip.io"
    echo "  - kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller"
    echo "  - kubectl get certificates"
    echo ""
    log_info "🌐 Direct access without configuration:"
    echo "  - Dashboard: https://dashboard.127.0.0.1.nip.io"
    echo "  - Test nginx: https://shadok.127.0.0.1.nip.io"
    echo ""

    # Display pod status
    log_info "📊 System pod status:"
    kubectl get pods -A -o wide | grep -E "(cert-manager|ingress-nginx|kubernetes-dashboard|curl-test)"
    echo ""

    # Display ingresses
    log_info "🌐 Configured ingresses:"
    kubectl get ingress -A
}

# Quick test function
test_configuration() {
    log_info "🧪 === Quick configuration test ==="

    # Test access to the shadok nginx service via ingress
    if curl -s -k -o /dev/null -w "%{http_code}" https://shadok.127.0.0.1.nip.io 2>/dev/null | grep -q "200"; then
        log_success "✅ Successfully accessed shadok nginx service via ingress"
    else
        log_warning "⚠️  Unable to access shadok nginx service via ingress"
    fi
}

# Create necessary namespaces
create_namespaces() {
    log_info "📁 Creating necessary namespaces..."

    # Create the shadok namespace for the operator
    kubectl create namespace shadok --dry-run=client -o yaml | kubectl apply -f -
    log_success "✅ Shadok namespace created"
}

# Main function
main() {
    log_info "🚀 === Advanced configuration of kind cluster '${CLUSTER_NAME}' ==="
    echo ""

    check_prerequisites
    create_namespaces
    echo ""

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

# Execute the main script
main "$@"
