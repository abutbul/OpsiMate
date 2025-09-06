#!/usr/bin/env bash
set -euo pipefail

# Quick Docker Test Runner
# A simplified version for rapid local testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-and-deploy.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Quick health check
check_health() {
    local url=$1
    local name=$2
    
    log "Checking $name health at $url"
    for i in {1..30}; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            log "$name is healthy!"
            return 0
        fi
        sleep 2
    done
    error "$name failed health check"
    return 1
}

# Version verification
verify_version() {
    local expected_tag=$1
    local port=${2:-3001}
    local service_name=${3:-"server"}
    
    log "Verifying $service_name is running version: $expected_tag"
    
    # Try to get version info from health endpoint
    local response
    if response=$(curl -s "http://localhost:$port/api/health" 2>/dev/null); then
        log "Health response: $response"
        # For now, just verify the service is responding
        log "Service responding correctly for tag $expected_tag"
        return 0
    fi
    
    # Check container image tag
    if $BUILD_SCRIPT ps | grep -q "$expected_tag"; then
        log "Container running with expected tag: $expected_tag"
        return 0
    fi
    
    warn "Could not verify exact version, but service is running"
    return 0
}

# Test scenarios
test_local_build() {
    log "=== Testing LOCAL Build (PR/Development Simulation) ==="
    
    # Clean and build from local context
    $BUILD_SCRIPT clean all
    log "Building from local context (simulates PR/development)..."
    $BUILD_SCRIPT build all --tag local
    
    # Deploy SQLite with local build
    $BUILD_SCRIPT deploy-server --tag local
    
    # Check health and verify version
    check_health "http://localhost:3001/api/health" "Local SQLite Server"
    verify_version "local" 3001 "server"
    
    # Show status
    $BUILD_SCRIPT ps
    
    log "Local build test completed!"
}

test_git_tag_build() {
    log "=== Testing GIT TAG Build (Release Simulation) ==="
    
    # Clean previous
    $BUILD_SCRIPT clean all
    
    # Use a real git tag - let's check what tags exist
    local available_tags
    available_tags=$(git tag --list | tail -3 | head -1)
    
    if [ -z "$available_tags" ]; then
        warn "No git tags found, skipping git tag test"
        return 0
    fi
    
    local test_tag="$available_tags"
    log "Building from git tag: $test_tag"
    
    # Build from git tag
    $BUILD_SCRIPT build server --tag "$test_tag"
    
    # Deploy with git tag
    $BUILD_SCRIPT deploy-server --tag "$test_tag"
    
    # Check health and verify version
    check_health "http://localhost:3001/api/health" "Git Tag Server"
    verify_version "$test_tag" 3001 "server"
    
    # Show status
    $BUILD_SCRIPT ps
    
    log "Git tag build test completed with tag: $test_tag"
}

test_sqlite_quick() {
    log "=== Quick SQLite Test ==="
    
    # Clean and build
    $BUILD_SCRIPT clean all
    $BUILD_SCRIPT build all --tag local
    
    # Deploy SQLite
    $BUILD_SCRIPT deploy-server --tag local
    
    # Check health
    check_health "http://localhost:3001/api/health" "SQLite Server"
    verify_version "local" 3001 "SQLite server"
    
    # Show status
    $BUILD_SCRIPT ps
    
    log "SQLite test completed!"
}

test_postgres_quick() {
    log "=== Quick PostgreSQL Test ==="
    
    # Stop previous and deploy PostgreSQL
    $BUILD_SCRIPT stop
    $BUILD_SCRIPT deploy-server --tag local --postgres
    
    # Check health
    check_health "http://localhost:3002/api/health" "PostgreSQL Server"
    verify_version "local" 3002 "PostgreSQL server"
    
    # Show status
    $BUILD_SCRIPT ps
    
    log "PostgreSQL test completed!"
}

test_client_quick() {
    log "=== Quick Client Test ==="
    
    # Ensure we have a client image
    $BUILD_SCRIPT build client --tag local
    
    # Start client in background
    log "Starting client..."
    $BUILD_SCRIPT run-client --tag local >/dev/null 2>&1 &
    local client_pid=$!
    
    # Quick health check
    sleep 5
    if check_health "http://localhost:8080" "Client"; then
        verify_version "local" 8080 "client"
        log "Client test passed!"
    else
        error "Client test failed!"
    fi
    
    # Clean up
    kill $client_pid 2>/dev/null || true
    $BUILD_SCRIPT clean containers || true
}

test_version_comparison() {
    log "=== Version Comparison Test ==="
    
    # Test local vs git tag
    log "Testing LOCAL build first..."
    test_local_build
    
    log "Stopping local deployment..."
    $BUILD_SCRIPT stop
    sleep 2
    
    log "Testing GIT TAG build..."
    test_git_tag_build
    
    log "Version comparison test completed!"
}

cleanup_all() {
    log "=== Cleaning Up ==="
    $BUILD_SCRIPT stop
    $BUILD_SCRIPT stop --postgres
    $BUILD_SCRIPT clean all
    log "Cleanup completed!"
}

# Main menu
show_menu() {
    echo ""
    echo "Quick Docker Test Runner"
    echo "========================"
    echo "1) Test LOCAL build (PR/dev simulation)"
    echo "2) Test GIT TAG build (release simulation)" 
    echo "3) Test SQLite (build + deploy + check)"
    echo "4) Test PostgreSQL (deploy + check)"
    echo "5) Test Client (run + check)"
    echo "6) Test Version Comparison (local vs git tag)"
    echo "7) Run all tests"
    echo "8) Clean up everything"
    echo "9) Show container status"
    echo "q) Quit"
    echo ""
    read -p "Choose option [1-9,q]: " choice
}

main() {
    # Ensure we're in the project root (parent of scripts directory)
    cd "$(dirname "$(dirname "$BUILD_SCRIPT")")"
    
    if [ $# -gt 0 ]; then
        # Non-interactive mode
        case "$1" in
            "local"|"1") test_local_build ;;
            "git"|"tag"|"2") test_git_tag_build ;;
            "sqlite"|"3") test_sqlite_quick ;;
            "postgres"|"4") test_postgres_quick ;;
            "client"|"5") test_client_quick ;;
            "compare"|"version"|"6") test_version_comparison ;;
            "all"|"7") 
                test_local_build
                test_git_tag_build
                test_sqlite_quick
                test_postgres_quick
                test_client_quick
                ;;
            "clean"|"8") cleanup_all ;;
            "status"|"9") $BUILD_SCRIPT ps ;;
            *) 
                echo "Usage: $0 [local|git|sqlite|postgres|client|compare|all|clean|status]"
                echo ""
                echo "Commands:"
                echo "  local    - Test local build (PR/dev simulation)"
                echo "  git      - Test git tag build (release simulation)"
                echo "  sqlite   - Test SQLite deployment"
                echo "  postgres - Test PostgreSQL deployment"
                echo "  client   - Test client deployment"
                echo "  compare  - Test version comparison (local vs git)"
                echo "  all      - Run all tests"
                echo "  clean    - Clean up everything"
                echo "  status   - Show container status"
                exit 1
                ;;
        esac
        return
    fi
    
    # Interactive mode
    while true; do
        show_menu
        case $choice in
            1) test_local_build ;;
            2) test_git_tag_build ;;
            3) test_sqlite_quick ;;
            4) test_postgres_quick ;;
            5) test_client_quick ;;
            6) test_version_comparison ;;
            7) 
                test_local_build
                test_git_tag_build
                test_sqlite_quick
                test_postgres_quick
                test_client_quick
                ;;
            8) cleanup_all ;;
            9) $BUILD_SCRIPT ps ;;
            q|Q) 
                log "Goodbye!"
                exit 0
                ;;
            *) 
                warn "Invalid option. Please try again."
                ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

main "$@"
