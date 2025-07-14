#!/bin/bash

# Script de déploiement des ressources CRD de test pour Shadok
# Ce script prépare l'environnement pour tester le webhook

set -e

echo "🚀 Déploiement des ressources CRD de test pour Shadok"

# Configuration
NAMESPACE="shadok"
CONTEXT="kind-shadok-dev"

# Vérifier que kubectl est configuré
if ! kubectl cluster-info --context $CONTEXT > /dev/null 2>&1; then
    echo "❌ Cluster Kind non accessible. Vérifiez que 'kind-shadok-dev' est démarré."
    exit 1
fi

echo "✅ Cluster Kind 'shadok-dev' accessible"

# Créer le namespace shadok s'il n'existe pas
echo "📦 Création du namespace ${NAMESPACE}..."
kubectl create namespace $NAMESPACE --context $CONTEXT --dry-run=client -o yaml | kubectl apply --context $CONTEXT -f -

# Appliquer les CRDs de Shadok depuis l'opérateur
echo "🔧 Application des CRDs Shadok..."
SHADOK_DIR="/Users/alexandreboyer/dev/kub/shadok/shadok"

if [ -d "$SHADOK_DIR/build/kubernetes" ]; then
    echo "   Deploying CRDs from operator build..."
    for crd_file in "$SHADOK_DIR/build/kubernetes"/*.yml; do
        if [[ -f "$crd_file" && "$crd_file" == *"shadok.org"* ]]; then
            echo "   Applying $(basename $crd_file)..."
            kubectl apply --context $CONTEXT -f "$crd_file"
        fi
    done
else
    echo "   ⚠️  CRDs not found in operator build. Building first..."
    cd "$SHADOK_DIR"
    ./gradlew build -q
    echo "   Applying generated CRDs..."
    for crd_file in "$SHADOK_DIR/build/kubernetes"/*.yml; do
        if [[ -f "$crd_file" && "$crd_file" == *"shadok.org"* ]]; then
            echo "   Applying $(basename $crd_file)..."
            kubectl apply --context $CONTEXT -f "$crd_file"
        fi
    done
fi

# Appliquer les ressources de test pour quarkus-hello
echo "🧪 Application des ressources de test..."
kubectl apply --context $CONTEXT -f k8s/shadok-resources.yml

# Vérifier que les ressources sont créées
echo "🔍 Vérification des ressources créées..."
echo ""
echo "📋 CRDs Shadok:"
kubectl get crd --context $CONTEXT | grep shadok.org || echo "   Aucune CRD trouvée"

echo ""
echo "🏗️  Applications:"
kubectl get applications.shadok.org -n $NAMESPACE --context $CONTEXT || echo "   Aucune Application trouvée"

echo ""
echo "📁 ProjectSources:"
kubectl get projectsources.shadok.org -n $NAMESPACE --context $CONTEXT || echo "   Aucune ProjectSource trouvée"

echo ""
echo "💾 DependencyCaches:"
kubectl get dependencycaches.shadok.org -n $NAMESPACE --context $CONTEXT || echo "   Aucune DependencyCache trouvée"

echo ""
echo "💿 PVCs:"
kubectl get pvc -n $NAMESPACE --context $CONTEXT || echo "   Aucune PVC trouvée"

echo ""
echo "✅ Déploiement des ressources CRD terminé!"
echo "📌 Le namespace '$NAMESPACE' est maintenant prêt pour tester le webhook"
