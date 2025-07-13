#!/bin/bash

# Script de test pour l'application Python Hello World

BASE_URL="http://localhost:8000"

echo "🧪 Test des endpoints de l'application Python Hello World"
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

# Test endpoint racine
echo "3️⃣  Test GET / (informations générales)"
curl -s "$BASE_URL/" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/"
echo -e "\n"

# Test health check
echo "4️⃣  Test GET /health (health check)"
curl -s "$BASE_URL/health" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/health"
echo -e "\n"

# Test documentation Swagger
echo "5️⃣  Test GET /docs (documentation Swagger)"
curl -s -I "$BASE_URL/docs" | head -1
echo ""

# Test schéma OpenAPI
echo "6️⃣  Test GET /openapi.json (schéma OpenAPI)"
curl -s -I "$BASE_URL/openapi.json" | head -1
echo ""

echo "✅ Tests terminés!"
echo "🌐 Pour accéder à la documentation: $BASE_URL/docs"
