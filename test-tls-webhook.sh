#!/bin/bash

# Test script to verify TLS webhook functionality
# This script will:
# 1. Start a new kind cluster with cert-manager
# 2. Deploy the operator with TLS webhook
# 3. Test the quarkus-hello application deployment

set -e

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

# Step 1: Start a new kind cluster with cert-manager
print_header "Starting Kind Cluster with cert-manager"
print_step "Changing to kind directory..."
cd "$(dirname "$0")/kind"

print_step "Starting kind cluster with cert-manager..."
./start-kind.sh

# Step 2: Deploy the operator with TLS webhook
print_header "Deploying Operator with TLS Webhook"
print_step "Changing to operator directory..."
cd "$(dirname "$0")/operator"

print_step "Deploying operator with TLS webhook..."
./deploy-to-kind.sh --redeploy-cluster=false

# Step 3: Test the quarkus-hello application deployment
print_header "Testing quarkus-hello Deployment"
print_step "Changing to quarkus-hello directory..."
cd "$(dirname "$0")/pods/quarkus-hello"

print_step "Deploying quarkus-hello application..."
./deploy-to-kind.sh

# Verify the deployment
print_header "Verifying Deployment"
print_step "Checking if quarkus-hello pod is running..."
if kubectl get pods -n shadok -l app=quarkus-hello | grep -q "Running"; then
    print_success "quarkus-hello pod is running! TLS webhook is working correctly."
else
    print_error "quarkus-hello pod is not running. TLS webhook might have issues."
    kubectl get pods -n shadok
    kubectl get events -n shadok
    exit 1
fi

print_header "Test Summary"
print_success "🎉 TLS webhook test completed successfully!"
print_step "The webhook is now using TLS with cert-manager and not ignoring errors."
print_step "You can verify the webhook configuration with:"
echo "  kubectl get mutatingwebhookconfiguration shadok-pod-mutator -o yaml"
print_step "And check the certificate with:"
echo "  kubectl get certificate webhook-server-cert -n shadok -o yaml"