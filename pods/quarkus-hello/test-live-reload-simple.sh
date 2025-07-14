#!/bin/bash

# 🧪 Test Live Reload avec Modifications Sed - Quarkus Hello
# ================================================================
#
# Ce script teste la recompilation automatique en temps réel du webservice
# quarkus-hello en utilisant sed pour modifier le code source.
#
# Workflow testé :
# 1. Test endpoint initial (/hello/json)
# 2. Modification du code avec sed
# 3. Vérification recompilation automatique + nouveau comportement
# 4. Restauration du code original
# 5. Vérification retour au comportement initial
#
# Usage: ./test-live-reload-simple.sh [options]

set -e

# ========================================
# 🎨 Configuration
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="shadok"
TIMEOUT=30
VERBOSE=false
BASE_URL="https://quarkus-hello.127.0.0.1.nip.io"
CURL_OPTS="-k -s"

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

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}🔍 $1${NC}"
    fi
}

# ========================================
# 🔍 Tests HTTP des Endpoints
# ========================================

test_endpoint() {
    local description="$1"
    local expected_pattern="$2"
    
    print_step "Test: $description"
    
    local response=$(curl $CURL_OPTS "$BASE_URL/hello/json" 2>/dev/null || echo "ERROR")
    log_verbose "Réponse HTTP: $response"
    
    if [[ "$response" == *"$expected_pattern"* ]]; then
        print_success "✅ Test réussi - Pattern trouvé: $expected_pattern"
        if [ "$VERBOSE" = true ]; then
            echo "  Réponse: $response"
        fi
        return 0
    else
        print_error "❌ Test échoué - Pattern attendu: $expected_pattern"
        echo "  Réponse reçue: $response"
        return 1
    fi
}

wait_for_endpoint_change() {
    local expected_pattern="$1"
    local max_attempts="$2"
    local attempt=0
    
    print_step "Attente du changement d'endpoint (max ${max_attempts}s)..."
    
    while [ $attempt -lt $max_attempts ]; do
        sleep 1
        ((attempt++))
        
        local response=$(curl $CURL_OPTS "$BASE_URL/hello/json" 2>/dev/null || echo "ERROR")
        if [[ "$response" == *"$expected_pattern"* ]]; then
            print_success "Changement détecté après ${attempt}s !"
            return 0
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log_verbose "Tentative $attempt/$max_attempts - En attente..."
        fi
    done
    
    print_error "Timeout: Aucun changement détecté après ${max_attempts}s"
    return 1
}

# ========================================
# 🚀 Vérification de la Connectivité
# ========================================

verify_connectivity() {
    print_header "Vérification de la Connectivité"
    
    print_step "Test de connectivité vers $BASE_URL..."
    
    if curl $CURL_OPTS "$BASE_URL/hello" > /dev/null 2>&1; then
        print_success "Ingress accessible et endpoint fonctionnel"
        return 0
    else
        print_error "Impossible de se connecter via l'Ingress"
        print_error "URL testée: $BASE_URL/hello"
        print_warning "Vérifiez que l'application quarkus-hello est déployée"
        return 1
    fi
}

# ========================================
# 🎯 Test Principal de Live Reload
# ========================================

run_live_reload_test() {
    print_header "Test Live Reload avec Modifications Sed"
    
    # Étape 1: Vérification de la connectivité
    if ! verify_connectivity; then
        exit 1
    fi
    
    # Variables pour les fichiers
    local source_file="src/main/java/com/shadok/pods/quarkus/HelloWorldResource.java"
    local backup_file="${source_file}.backup"
    
    # Fonction de nettoyage
    cleanup() {
        print_step "Nettoyage..."
        if [ -f "$backup_file" ]; then
            mv "$backup_file" "$source_file"
            print_success "Fichier restauré depuis la sauvegarde"
        fi
        rm -f "${source_file}.tmp" 2>/dev/null || true
    }
    trap cleanup EXIT
    
    # Étape 2: Test état initial
    print_step "🔍 ÉTAPE 1: Test de l'état initial"
    if ! test_endpoint "État initial" "Hello World from Quarkus Pod!"; then
        print_error "Test initial échoué - Application pas accessible"
        exit 1
    fi
    
    # Étape 3: Application du patch
    print_step "🔧 ÉTAPE 2: Application des modifications avec sed"
    
    if [ ! -f "$source_file" ]; then
        print_error "Fichier source non trouvé: $source_file"
        exit 1
    fi
    
    # Sauvegarder le fichier original
    cp "$source_file" "$backup_file"
    print_success "Sauvegarde créée: $backup_file"
    
    # Appliquer la modification avec sed
    sed -i.tmp 's/Hello World from Quarkus Pod!/🧪 LIVE RELOAD TEST ACTIVE! 🚀/g' "$source_file"
    sed -i.tmp 's/"quarkus-hello"/"quarkus-hello-patched"/g' "$source_file"
    sed -i.tmp 's/"1.0.0"/"2.0.0-LIVE"/g' "$source_file"
    rm -f "${source_file}.tmp"
    
    print_success "Modifications appliquées avec sed"
    log_verbose "Modifications appliquées au fichier: $source_file"
    
    # Étape 4: Attendre la recompilation et test
    print_step "⏱️  ÉTAPE 3: Attente de la recompilation automatique"
    if wait_for_endpoint_change "LIVE RELOAD TEST ACTIVE" $TIMEOUT; then
        print_success "🎉 Recompilation automatique détectée !"
        
        # Test de validation
        if test_endpoint "Après modification" "quarkus-hello-patched"; then
            print_success "✅ Modification confirmée"
        else
            print_warning "⚠️  Recompilation détectée mais modification partielle"
        fi
    else
        print_error "❌ Recompilation automatique non détectée"
        print_warning "Possible raisons:"
        print_warning "  • Live reload non activé dans le pod"
        print_warning "  • Volumes source non montés"
        print_warning "  • Quarkus dev mode non actif"
        exit 1
    fi
    
    # Étape 5: Revert du patch
    print_step "🔄 ÉTAPE 4: Restauration du code original"
    mv "$backup_file" "$source_file"
    print_success "Code original restauré"
    
    # Étape 6: Test du retour à l'état initial
    print_step "🔍 ÉTAPE 5: Vérification du retour à l'état initial"
    if wait_for_endpoint_change "Hello World from Quarkus Pod!" $TIMEOUT; then
        print_success "🎉 Retour à l'état initial confirmé !"
        
        # Test final de validation
        if test_endpoint "État final" "quarkus-hello"; then
            print_success "✅ Test de live reload complet réussi !"
            return 0
        else
            print_warning "⚠️  Retour partiel à l'état initial"
            return 1
        fi
    else
        print_error "❌ Retour à l'état initial non détecté"
        return 1
    fi
}

# ========================================
# 📊 Rapport de Test
# ========================================

generate_test_report() {
    local test_result=$1
    
    print_header "Rapport de Test Live Reload"
    
    if [ $test_result -eq 0 ]; then
        echo "🏆 RÉSULTAT: SUCCÈS COMPLET"
        echo ""
        echo "✅ Fonctionnalités validées:"
        echo "  • Live reload automatique actif"
        echo "  • Recompilation en temps réel fonctionnelle"
        echo "  • Détection des changements de code"
        echo "  • Endpoints HTTP réactifs aux modifications"
        echo "  • Workflow modification/restauration opérationnel"
        echo ""
        echo "📈 Métriques:"
        echo "  • Timeout configuré: ${TIMEOUT}s"
        echo "  • URL testée: $BASE_URL"
        echo "  • Namespace: $NAMESPACE"
        echo ""
        print_success "🚀 Le live reload Quarkus fonctionne parfaitement !"
    else
        echo "❌ RÉSULTAT: ÉCHEC"
        echo ""
        echo "🔧 Points à vérifier:"
        echo "  • L'application dispose-t-elle du live reload activé ?"
        echo "  • Les volumes source/cache sont-ils montés ?"
        echo "  • Quarkus dev mode est-il actif dans le conteneur ?"
        echo "  • La commande './gradlew quarkusDev' est-elle utilisée ?"
        echo ""
        print_error "⚠️  Le live reload nécessite une configuration supplémentaire"
    fi
}

# ========================================
# 📚 Aide
# ========================================

show_help() {
    echo "🧪 Test Live Reload avec Modifications Sed - Quarkus Hello"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --timeout SECS     Timeout recompilation (défaut: 30s)"
    echo "  --verbose          Logs détaillés"
    echo "  --help             Affiche cette aide"
    echo ""
    echo "Prérequis:"
    echo "  • Application quarkus-hello déployée avec Ingress actif"
    echo "  • Ingress accessible via $BASE_URL"
    echo "  • curl installé"
    echo ""
    echo "Exemples:"
    echo "  $0                           # Test automatique"
    echo "  $0 --verbose                 # Avec logs détaillés"
    echo "  $0 --timeout 60              # Timeout personnalisé"
    echo ""
}

# ========================================
# 🚀 Main
# ========================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Header
    echo -e "${PURPLE}"
    echo "🧪 ============================================ 🧪"
    echo "   Test Live Reload avec Modifications Sed"
    echo "     Quarkus Hello - Webservice"
    echo "=============================================="
    echo -e "${NC}"
    
    # Vérifications préalables
    if ! command -v curl > /dev/null 2>&1; then
        print_error "curl non disponible"
        exit 1
    fi
    
    # Vérifier qu'on est dans le bon répertoire
    if [ ! -f "src/main/java/com/shadok/pods/quarkus/HelloWorldResource.java" ]; then
        print_error "Doit être exécuté depuis le répertoire pods/quarkus-hello"
        exit 1
    fi
    
    # Exécuter le test
    run_live_reload_test
    local result=$?
    
    # Générer le rapport
    generate_test_report $result
    
    exit $result
}

main "$@"
