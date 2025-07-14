#!/bin/bash

# Script de test manuel pour le webhook Shadok
# Usage: ./test-webhook.sh [COMMAND]

BASE_URL="http://localhost:8080"
WEBHOOK_TEST_URL="${BASE_URL}/webhook-test"

function test_health() {
    echo "🏥 Test de santé du webhook..."
    curl -s "${WEBHOOK_TEST_URL}/health" | jq '.'
}

function test_application_types() {
    echo "📋 Liste des types d'applications supportés..."
    curl -s "${WEBHOOK_TEST_URL}/application-types" | jq '.'
}

function test_mutation() {
    local app_name=${1:-"test-app"}
    local namespace=${2:-"test-namespace"}

    echo "🔄 Test de mutation pour l'application: ${app_name}"

    cat << EOF | curl -s -X POST "${WEBHOOK_TEST_URL}/test-mutation" \
        -H "Content-Type: application/json" \
        -d @- | jq '.'
{
    "podName": "test-pod",
    "namespace": "${namespace}",
    "applicationName": "${app_name}",
    "additionalAnnotations": {
        "test.shadok/origin": "manual-test"
    }
}
EOF
}

function test_application_type() {
    local app_type=${1:-"QUARKUS"}

    echo "🎯 Test de mutation pour le type: ${app_type}"
    curl -s -X POST "${WEBHOOK_TEST_URL}/test-application-type/${app_type}" \
        -H "Content-Type: application/json" | jq '.'
}

function test_all_types() {
    echo "🚀 Test de tous les types d'applications..."

    for app_type in SPRING QUARKUS NODE PYTHON GO RUBY PHP DOTNET OTHER; do
        echo "--- Testing ${app_type} ---"
        test_application_type "${app_type}"
        echo ""
    done
}

function show_help() {
    cat << EOF
🔧 Script de test manuel pour le webhook Shadok

Usage: $0 [COMMAND] [ARGS...]

Commandes disponibles:
  health                    - Test de santé du webhook
  types                     - Liste les types d'applications
  mutation [app] [ns]       - Test de mutation (défaut: test-app, test-namespace)
  app-type [TYPE]           - Test pour un type spécifique (défaut: QUARKUS)
  all-types                 - Test tous les types d'applications
  help                      - Affiche cette aide

Exemples:
  $0 health
  $0 mutation my-app my-namespace
  $0 app-type SPRING
  $0 all-types

Prérequis:
- L'application doit être lancée avec le profil debug: mvn quarkus:dev -Dquarkus.profile=debug
- jq doit être installé pour formater le JSON
EOF
}

# Parse command line arguments
case "${1:-help}" in
    "health")
        test_health
        ;;
    "types")
        test_application_types
        ;;
    "mutation")
        test_mutation "$2" "$3"
        ;;
    "app-type")
        test_application_type "$2"
        ;;
    "all-types")
        test_all_types
        ;;
    "help"|*)
        show_help
        ;;
esac
