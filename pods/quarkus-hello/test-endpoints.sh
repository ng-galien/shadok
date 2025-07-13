#!/bin/bash

# Script de test pour l'application Quarkus Hello World

BASE_URL="https://quarkus-hello.127.0.0.1.nip.io"
CURL_OPTS="-k -s"  # -k pour ignorer les certificats SSL self-signed, -s pour silent

echo "🧪 Test des endpoints de l'application Quarkus Hello World"
echo "📍 URL de base: $BASE_URL"
echo "🔒 Utilisation de HTTPS avec certificats auto-signés"
echo ""

# Test endpoint hello en texte
echo "1️⃣  Test GET /hello (text/plain)"
curl $CURL_OPTS "$BASE_URL/hello"
echo -e "\n"

# Test endpoint hello en JSON
echo "2️⃣  Test GET /hello/json (application/json)"
curl $CURL_OPTS -H "Accept: application/json" "$BASE_URL/hello/json" | jq .
echo -e "\n"

echo "✅ Tests terminés!"
