#!/bin/bash

# Script de test des endpoints pour l'application Node.js Hello World

set -e

BASE_URL="http://localhost:3000"
SUCCESS_COUNT=0
TOTAL_TESTS=0

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🧪 Test des endpoints Node.js Hello World"
echo "🌐 URL de base: $BASE_URL"
echo "======================================="

# Fonction de test d'endpoint
test_endpoint() {
  local method=$1
  local endpoint=$2
  local expected_status=$3
  local description=$4

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  echo -n "Testing $method $endpoint - $description... "

  if command -v curl &> /dev/null; then
    response=$(curl -s -w "%{http_code}" -X "$method" "$BASE_URL$endpoint" -o /tmp/response.txt)
    status_code="${response: -3}"

    if [ "$status_code" = "$expected_status" ]; then
      echo -e "${GREEN}✅ PASS${NC} (Status: $status_code)"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

      # Afficher un aperçu de la réponse pour les endpoints JSON
      if [[ "$endpoint" == *"json"* ]] || [[ "$endpoint" == "/" ]] || [[ "$endpoint" == "/health" ]] || [[ "$endpoint" == "/ready" ]]; then
        echo -e "   ${BLUE}Response preview:${NC} $(head -c 100 /tmp/response.txt)..."
      fi
    else
      echo -e "${RED}❌ FAIL${NC} (Expected: $expected_status, Got: $status_code)"
      echo -e "   ${YELLOW}Response:${NC} $(cat /tmp/response.txt)"
    fi
  else
    echo -e "${YELLOW}⚠️  SKIP${NC} (curl not available)"
  fi

  echo ""
}

# Vérification que le serveur est en cours d'exécution
echo "🔍 Vérification de la disponibilité du serveur..."
if curl -s --connect-timeout 5 "$BASE_URL/health" > /dev/null; then
  echo -e "${GREEN}✅ Serveur accessible${NC}"
else
  echo -e "${RED}❌ Serveur non accessible${NC}"
  echo "💡 Assurez-vous que le serveur Node.js est démarré sur $BASE_URL"
  echo "   Commande: ./start.sh dev"
  exit 1
fi

echo ""

# Tests des endpoints
test_endpoint "GET" "/" "200" "Service information"
test_endpoint "GET" "/hello" "200" "Simple greeting"
test_endpoint "GET" "/hello/json" "200" "Detailed JSON response"
test_endpoint "GET" "/health" "200" "Health check"
test_endpoint "GET" "/ready" "200" "Readiness check"
test_endpoint "GET" "/nonexistent" "404" "404 error handling"

# Nettoyage
rm -f /tmp/response.txt

# Résumé
echo "======================================="
echo "📊 Résumé des tests:"
echo -e "   Tests réussis: ${GREEN}$SUCCESS_COUNT${NC}/$TOTAL_TESTS"

if [ $SUCCESS_COUNT -eq $TOTAL_TESTS ]; then
  echo -e "   ${GREEN}🎉 Tous les tests ont réussi !${NC}"
  exit 0
else
  FAILED_TESTS=$((TOTAL_TESTS - SUCCESS_COUNT))
  echo -e "   ${RED}❌ $FAILED_TESTS test(s) ont échoué${NC}"
  exit 1
fi
