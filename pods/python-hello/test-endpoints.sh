#!/bin/bash

# Endpoint test script for the Python Hello World application

BASE_URL="http://localhost:8000"

echo "🧪 Testing Python Hello World endpoints"
echo "📍 Base URL: $BASE_URL"
echo ""

# Test the plain-text greeting endpoint
echo "1️⃣  Test GET /hello (text/plain)"
curl -s "$BASE_URL/hello"
echo -e "\n"

# Test the JSON greeting endpoint
echo "2️⃣  Test GET /hello/json (application/json)"
curl -s -H "Accept: application/json" "$BASE_URL/hello/json" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/hello/json"
echo -e "\n"

# Test the root endpoint
echo "3️⃣  Test GET / (general information)"
curl -s "$BASE_URL/" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/"
echo -e "\n"

# Test health check
echo "4️⃣  Test GET /health (health check)"
curl -s "$BASE_URL/health" | python3 -m json.tool 2>/dev/null || curl -s "$BASE_URL/health"
echo -e "\n"

# Test Swagger documentation
echo "5️⃣  Test GET /docs (Swagger documentation)"
curl -s -I "$BASE_URL/docs" | head -1
echo ""

# Test the OpenAPI schema
echo "6️⃣  Test GET /openapi.json (OpenAPI schema)"
curl -s -I "$BASE_URL/openapi.json" | head -1
echo ""

echo "✅ Tests completed!"
echo "🌐 Documentation is available at: $BASE_URL/docs"
