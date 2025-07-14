#!/bin/bash

# 🧪 Test de Live Reload - Webservice Quarkus Hello
# ================================================================
#
# Ce script teste la recompilation automatique du webservice quarkus-hello
# quand on modifie son code source
#
# Processus testé :
# 1. Déployer un pod avec le webservice quarkus-hello
# 2. Modifier le code source (endpoint /hello)
# 3. Vérifier que le webservice se recompile automatiquement
# 4. Tester que la modification est effective via HTTP

set -e

# ========================================
# 🎨 Configuration
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

NAMESPACE="shadok"
WEBSERVICE_DIR="pods/quarkus-hello"
ORIGINAL_MESSAGE="Hello World from Quarkus Pod!"
TEST_MESSAGE="🧪 Live Reload Test - $(date +%H:%M:%S)"

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

# ========================================
# 🏗️ Test de Live Reload du Webservice
# ========================================

test_webservice_live_reload() {
    print_header "Test Live Reload - Webservice Quarkus Hello"
    
    # 1. Vérifier que le webservice est déployé
    print_step "Vérification du pod quarkus-hello..."
    if ! kubectl get pod -l app=quarkus-hello -n $NAMESPACE > /dev/null 2>&1; then
        print_error "Pod quarkus-hello non trouvé. Déployez d'abord le webservice."
        return 1
    fi
    
    local pod_name=$(kubectl get pod -l app=quarkus-hello -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    print_success "Pod trouvé: $pod_name"
    
    # 2. Tester l'endpoint avant modification
    print_step "Test endpoint avant modification..."
    kubectl port-forward pod/$pod_name 8080:8080 -n $NAMESPACE &
    local port_forward_pid=$!
    sleep 3
    
    local original_response=$(curl -s http://localhost:8080/hello || echo "ERREUR")
    echo "  Réponse actuelle: $original_response"
    
    # 3. Sauvegarder et modifier le code source
    print_step "Modification du code source..."
    local source_file="$WEBSERVICE_DIR/src/main/java/com/shadok/pods/quarkus/HelloWorldResource.java"
    local backup_file="${source_file}.backup"
    
    if [ ! -f "$source_file" ]; then
        print_error "Fichier source non trouvé: $source_file"
        kill $port_forward_pid 2>/dev/null
        return 1
    fi
    
    # Créer une sauvegarde
    cp "$source_file" "$backup_file"
    print_success "Sauvegarde créée: $backup_file"
    
    # Modifier le message
    sed -i.tmp "s/$ORIGINAL_MESSAGE/$TEST_MESSAGE/g" "$source_file"
    rm -f "${source_file}.tmp"
    print_success "Code modifié avec le nouveau message: $TEST_MESSAGE"
    
    # 4. Attendre la recompilation automatique
    print_step "Attente de la recompilation automatique (30s max)..."
    
    local max_attempts=30
    local attempt=0
    local reload_detected=false
    
    while [ $attempt -lt $max_attempts ]; do
        sleep 1
        ((attempt++))
        
        # Vérifier si la recompilation est détectée dans les logs
        local logs=$(kubectl logs $pod_name -n $NAMESPACE --tail=10 2>/dev/null || echo "")
        if [[ "$logs" == *"Live reload"* ]] || [[ "$logs" == *"Hot reload"* ]] || [[ "$logs" == *"reloaded"* ]]; then
            reload_detected=true
            print_success "Recompilation détectée dans les logs (${attempt}s)"
            break
        fi
        
        # Test HTTP pour voir si le changement est effectif
        local current_response=$(curl -s http://localhost:8080/hello 2>/dev/null || echo "ERREUR")
        if [[ "$current_response" == *"$TEST_MESSAGE"* ]]; then
            reload_detected=true
            print_success "Changement détecté via HTTP (${attempt}s)"
            break
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            echo "  Tentative $attempt/$max_attempts..."
        fi
    done
    
    # 5. Vérifier le résultat final
    print_step "Vérification finale..."
    sleep 2
    
    local final_response=$(curl -s http://localhost:8080/hello || echo "ERREUR")
    echo "  Réponse finale: $final_response"
    
    if [[ "$final_response" == *"$TEST_MESSAGE"* ]]; then
        print_success "✅ LIVE RELOAD RÉUSSI ! Le webservice a bien été recompilé."
        print_success "Temps de recompilation: ${attempt}s"
    else
        print_error "❌ LIVE RELOAD ÉCHOUÉ ! Le webservice n'a pas été recompilé."
        echo "  Attendu: $TEST_MESSAGE"
        echo "  Reçu: $final_response"
    fi
    
    # 6. Restaurer le code original
    print_step "Restauration du code original..."
    mv "$backup_file" "$source_file"
    print_success "Code restauré"
    
    # Nettoyer
    kill $port_forward_pid 2>/dev/null || true
    
    if [ "$reload_detected" = true ]; then
        return 0
    else
        return 1
    fi
}

# ========================================
# 🎯 Test complet avec déploiement
# ========================================

test_full_webservice_lifecycle() {
    print_header "Test Complet - Déploiement + Live Reload"
    
    # 1. Déployer le webservice avec live reload activé
    print_step "Déploiement du webservice avec live reload..."
    
    # Créer un manifeste de test avec annotation Shadok
    cat << EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Pod
metadata:
  name: quarkus-hello-live-reload-test
  namespace: $NAMESPACE
  labels:
    app: quarkus-hello
    test: live-reload
  annotations:
    # Cette annotation déclenche le webhook pour live reload
    org.shadok/application: "test-app"
spec:
  containers:
  - name: quarkus-hello
    image: localhost:5001/quarkus-hello:latest
    ports:
    - containerPort: 8080
      name: http
    volumeMounts:
    - name: source-code
      mountPath: /workspace
    - name: gradle-cache
      mountPath: /cache/.gradle
    env:
    - name: GRADLE_USER_HOME
      value: /cache/.gradle
    # Commande live reload injectée par le webhook
    command: ["./gradlew", "quarkusDev"]
  volumes:
  - name: source-code
    hostPath:
      path: /tmp/quarkus-hello-source
      type: DirectoryOrCreate
  - name: gradle-cache
    hostPath:
      path: /tmp/gradle-cache
      type: DirectoryOrCreate
  restartPolicy: Never
EOF
    
    print_success "Pod de test déployé"
    
    # 2. Attendre que le pod soit prêt
    print_step "Attente du démarrage du pod..."
    kubectl wait --for=condition=ready pod/quarkus-hello-live-reload-test -n $NAMESPACE --timeout=60s
    
    # 3. Exécuter le test de live reload
    test_webservice_live_reload
    
    # 4. Nettoyer
    print_step "Nettoyage du pod de test..."
    kubectl delete pod quarkus-hello-live-reload-test -n $NAMESPACE --ignore-not-found=true
    
    print_success "Test complet terminé"
}

# ========================================
# 🚀 Main
# ========================================

main() {
    echo -e "${PURPLE}"
    echo "🧪 ============================================ 🧪"
    echo "   Test Live Reload - Webservice Quarkus"
    echo "=============================================="
    echo -e "${NC}"
    
    case "${1:-basic}" in
        "basic")
            test_webservice_live_reload
            ;;
        "full")
            test_full_webservice_lifecycle
            ;;
        "help")
            echo "Usage: $0 [basic|full|help]"
            echo "  basic - Test live reload sur pod existant"
            echo "  full  - Test complet avec déploiement"
            echo "  help  - Affiche cette aide"
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Usage: $0 [basic|full|help]"
            exit 1
            ;;
    esac
}

# Vérifier le répertoire de travail
if [ ! -d "$WEBSERVICE_DIR" ]; then
    print_error "Répertoire $WEBSERVICE_DIR non trouvé. Exécutez depuis la racine du projet."
    exit 1
fi

main "$@"
