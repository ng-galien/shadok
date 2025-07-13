#!/bin/bash

# Script de test pour l'application Quarkus Hello World

BASE_URL="http://localhost:8080"

echo "🧪 Test des endpoints de l'application Quarkus Hello World"
echo "📍 URL de base: $BASE_URL"
echo ""

# Test endpoint hello en texte
echo "1️⃣  Test GET /hello (text/plain)"
curl -s "$BASE_URL/hello"
echo -e "\n"

# Test endpoint hello en JSON
echo "2️⃣  Test GET /hello/json (application/json)"
curl -s -H "Accept: application/json" "$BASE_URL/hello/json" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/hello/json"
echo -e "\n"

# Test health check
echo "3️⃣  Test GET /q/health (health check)"
curl -s "$BASE_URL/q/health" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/q/health"
echo -e "\n"

# Test liveness probe
echo "4️⃣  Test GET /q/health/live (liveness probe)"
curl -s "$BASE_URL/q/health/live"
echo -e "\n"

# Test readiness probe
echo "5️⃣  Test GET /q/health/ready (readiness probe)"
curl -s "$BASE_URL/q/health/ready"
echo -e "\n"

echo "✅ Tests terminés!"
