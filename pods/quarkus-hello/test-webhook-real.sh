#!/bin/bash

# Test du webhook avec l'application Quarkus réelle
# Ce script simule le déploiement d'un Pod avec les annotations Shadok

BASE_URL="http://localhost:8080"
WEBHOOK_TEST_URL="${BASE_URL}/webhook-test"

echo "🧪 Test du webhook avec l'application Quarkus réelle"

# Test avec les données exactes de l'application quarkus-hello
cat << 'EOF' | curl -s -X POST "${WEBHOOK_TEST_URL}/test-mutation" \
    -H "Content-Type: application/json" \
    -d @- | jq '.'
{
    "podName": "quarkus-hello-pod",
    "namespace": "shadok",
    "applicationName": "quarkus-hello-app",
    "additionalAnnotations": {
        "app.quarkus.io/quarkus-version": "3.8.1",
        "app.kubernetes.io/managed-by": "quarkus"
    }
}
EOF

echo ""
echo "✅ Test terminé - vérifiez si la mutation s'est bien appliquée!"
