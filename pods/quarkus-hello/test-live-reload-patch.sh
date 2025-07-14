#!/bin/bash

# 🧪 Test Live Reload avec Git Patches - Quarkus Hello
# ================================================================
#
# Ce script teste la recompilation automatique en temps réel du webservice
# quarkus-hello en utilisant des patches Git pour simuler des modifications
# de code réalistes.
#
# Workflow testé :
# 1. Test endpoint initial (/hello/json)
# 2. Application d'un patch Git (modification helloJson)
# 3. Vérification recompilation automatique + nouveau comportement
# 4. Revert du patch
# 5. Vérification retour au comportement initial
#
# Usage: ./test-live-reload-patch.sh [options]
# Options:
#   --pod-name NAME    Nom du pod à tester (défaut: auto-detect)
#   --namespace NS     Namespace (défaut: shadok)
#   --timeout SECS     Timeout pour la recompilation (défaut: 30s)
#   --verbose          Logs détaillés

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
POD_NAME=""
TIMEOUT=30
VERBOSE=false
BASE_URL="https://quarkus-hello.127.0.0.1.nip.io"
CURL_OPTS="-k -s"  # -k pour ignorer les certificats SSL self-signed, -s pour silent

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
# 🎯 Création du Patch Git
# ========================================

create_live_reload_patch() {
    print_header "Création du Patch Git de Test"
    
    local patch_file="live-reload-test.patch"
    
    print_step "Génération du patch pour modification de helloJson()..."
    
    # Plutôt qu'un patch Git complexe, utilisons sed pour une modification simple et robuste
    print_success "Patch sera appliqué via sed (plus robuste)"
    log_verbose "Modification: HelloWorldResource.java -> méthode helloJson()"
    
    echo "sed_patch" > "$patch_file"
    echo "$patch_file"
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
        echo "$response"
        return 0
    else
        print_error "❌ Test échoué - Pattern attendu: $expected_pattern"
        echo "Réponse reçue: $response"
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
# 🚀 Vérification de la Connectivité Ingress
# ========================================

verify_ingress_connectivity() {
    print_header "Vérification de la Connectivité via Ingress"
    
    print_step "Test de connectivité vers $BASE_URL..."
    
    # Test simple de connectivité
    if curl $CURL_OPTS "$BASE_URL/hello" > /dev/null 2>&1; then
        print_success "Ingress accessible et endpoint fonctionnel"
        return 0
    else
        print_error "Impossible de se connecter via l'Ingress"
        print_error "URL testée: $BASE_URL/hello"
        print_warning "Vérifiez que:"
        print_warning "  • L'Ingress est configuré et actif"
        print_warning "  • Le service quarkus-hello existe"
        print_warning "  • Un pod quarkus-hello est en cours d'exécution"
        return 1
    fi
}

# ========================================
# 🎯 Test Principal de Live Reload
# ========================================

run_live_reload_test() {
    print_header "Test Live Reload avec Modifications Sed"
    
    local patch_file=$(create_live_reload_patch)
    
    # Étape 1: Vérification de la connectivité Ingress
    if ! verify_ingress_connectivity; then
        return 1
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
        rm -f "$patch_file" 2>/dev/null || true
        rm -f "${source_file}.tmp" 2>/dev/null || true
    }
    trap cleanup EXIT
    
    # Étape 2: Test état initial
    print_step "🔍 ÉTAPE 1: Test de l'état initial"
    if ! test_endpoint "État initial" "Hello World from Quarkus Pod!"; then
        print_error "Test initial échoué"
        return 1
    fi
    
    # Étape 3: Application du patch
    print_step "🔧 ÉTAPE 2: Application du patch avec sed"
    
    if [ ! -f "$source_file" ]; then
        print_error "Fichier source non trouvé: $source_file"
        return 1
    fi
    
    # Sauvegarder le fichier original
    cp "$source_file" "$backup_file"
    print_success "Sauvegarde créée: $backup_file"
    
    # Appliquer la modification avec sed
    sed -i.tmp 's/Hello World from Quarkus Pod!/🧪 LIVE RELOAD TEST ACTIVE! 🚀/g' "$source_file"
    sed -i.tmp 's/"quarkus-hello"/"quarkus-hello-patched"/g' "$source_file"
    sed -i.tmp 's/"1.0.0"/"2.0.0-LIVE"/g' "$source_file"
    rm -f "${source_file}.tmp"
    
    print_success "Patch appliqué avec sed"
    log_verbose "Modifications appliquées au fichier: $source_file"
    
    # Étape 4: Attendre la recompilation et test
    print_step "⏱️  ÉTAPE 3: Attente de la recompilation automatique"
    if wait_for_endpoint_change "LIVE RELOAD TEST ACTIVE" $TIMEOUT; then
        print_success "🎉 Recompilation automatique détectée !"
        
        # Test de validation
        if test_endpoint "Après patch" "quarkus-hello-patched"; then
            print_success "✅ Modification du patch confirmée"
        else
            print_warning "⚠️  Recompilation détectée mais modification partielle"
        fi
    else
        print_error "❌ Recompilation automatique non détectée"
        return 1
    fi
    
    # Étape 5: Revert du patch
    print_step "🔄 ÉTAPE 4: Revert du patch"
    mv "$backup_file" "$source_file"
    print_success "Patch reverté"
    
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
    if ! test_endpoint "État initial" "Hello World from Quarkus Pod!"; then
        print_error "Test initial échoué"
        return 1
    fi
    
    # Étape 3: Application du patch
    print_step "🔧 ÉTAPE 2: Application du patch Git"
    if git apply "$patch_file" 2>/dev/null; then
        print_success "Patch appliqué avec succès"
    else
        print_error "Échec d'application du patch"
        return 1
    fi
    
    # Étape 4: Attendre la recompilation et test
    print_step "⏱️  ÉTAPE 3: Attente de la recompilation automatique"
    if wait_for_endpoint_change "LIVE RELOAD TEST ACTIVE" $TIMEOUT; then
        print_success "🎉 Recompilation automatique détectée !"
        
        # Test de validation
        if test_endpoint "Après patch" "quarkus-hello-patched"; then
            print_success "✅ Modification du patch confirmée"
        else
            print_warning "⚠️  Recompilation détectée mais modification partielle"
        fi
    else
        print_error "❌ Recompilation automatique non détectée"
        return 1
    fi
    
    # Étape 5: Revert du patch
    print_step "🔄 ÉTAPE 4: Revert du patch Git"
    git checkout -- . 2>/dev/null
    print_success "Patch reverté"
    
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
        echo "  • Workflow Git patch/revert opérationnel"
        echo "  • Endpoints HTTP réactifs aux modifications"
        echo ""
        echo "📈 Métriques:"
        echo "  • Timeout configuré: ${TIMEOUT}s"
        echo "  • Pod testé: $POD_NAME"
        echo "  • Namespace: $NAMESPACE"
        echo ""
        print_success "🚀 Le live reload Quarkus est pleinement opérationnel !"
    else
        echo "❌ RÉSULTAT: ÉCHEC"
        echo ""
        echo "🔧 Points à vérifier:"
        echo "  • Le pod dispose-t-il du live reload activé ?"
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
    echo "🧪 Test Live Reload avec Git Patches - Quarkus Hello"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --pod-name NAME    Nom du pod à tester (défaut: auto-détection)"
    echo "  --namespace NS     Namespace Kubernetes (défaut: shadok)"
    echo "  --timeout SECS     Timeout recompilation (défaut: 30s)"
    echo "  --verbose          Logs détaillés"
    echo "  --help             Affiche cette aide"
    echo ""
    echo "Prérequis:"
    echo "  • Application quarkus-hello déployée avec Ingress actif"
    echo "  • Ingress accessible via $BASE_URL"
    echo "  • kubectl configuré et accessible"
    echo "  • curl installé"
    echo "  • git disponible dans le répertoire courant"
    echo ""
    echo "Exemples:"
    echo "  $0                           # Test automatique"
    echo "  $0 --verbose                 # Avec logs détaillés"
    echo "  $0 --pod-name my-pod         # Pod spécifique"
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
            --pod-name)
                POD_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
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
    echo "   Test Live Reload avec Git Patches"
    echo "     Quarkus Hello - Webservice"
    echo "=============================================="
    echo -e "${NC}"
    
    # Vérifications préalables
    if ! command -v kubectl > /dev/null 2>&1; then
        print_error "kubectl non disponible"
        exit 1
    fi
    
    if ! command -v curl > /dev/null 2>&1; then
        print_error "curl non disponible"
        exit 1
    fi
    
    if ! command -v git > /dev/null 2>&1; then
        print_error "git non disponible"
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
