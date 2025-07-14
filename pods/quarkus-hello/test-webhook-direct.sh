#!/bin/bash

# Test du webhook principal avec une AdmissionReview réaliste
# Ce script simule exactement ce que Kubernetes enverrait au webhook

BASE_URL="http://localhost:8080"
WEBHOOK_URL="${BASE_URL}/mutate-pods"

echo "🔧 Test direct du webhook principal avec AdmissionReview"

# Créer une AdmissionReview complète avec le Pod de l'application quarkus-hello
cat << 'EOF' | curl -s -X POST "${WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    -d @- | jq '.'
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "test-admission-12345",
    "kind": {
      "group": "",
      "version": "v1",
      "kind": "Pod"
    },
    "resource": {
      "group": "",
      "version": "v1",
      "resource": "pods"
    },
    "namespace": "shadok",
    "operation": "CREATE",
    "object": {
      "apiVersion": "v1",
      "kind": "Pod",
      "metadata": {
        "name": "quarkus-hello-test",
        "namespace": "shadok",
        "annotations": {
          "org.shadok/application": "quarkus-hello-app",
          "app.quarkus.io/quarkus-version": "3.8.1"
        },
        "labels": {
          "app.kubernetes.io/name": "quarkus-hello",
          "app.kubernetes.io/version": "1.0.0-SNAPSHOT",
          "app": "quarkus-hello"
        }
      },
      "spec": {
        "containers": [
          {
            "name": "quarkus-hello",
            "image": "docker.io/shadok-pods/quarkus-hello:latest",
            "ports": [
              {
                "containerPort": 8080,
                "name": "http",
                "protocol": "TCP"
              }
            ],
            "env": [
              {
                "name": "KUBERNETES_NAMESPACE",
                "valueFrom": {
                  "fieldRef": {
                    "fieldPath": "metadata.namespace"
                  }
                }
              }
            ],
            "resources": {
              "limits": {
                "cpu": "500m",
                "memory": "512Mi"
              },
              "requests": {
                "cpu": "100m",
                "memory": "256Mi"
              }
            }
          }
        ],
        "serviceAccountName": "default"
      }
    }
  }
}
EOF

echo ""
echo "✅ Test direct terminé - vérifiez la réponse AdmissionReview!"
