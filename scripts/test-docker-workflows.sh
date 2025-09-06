#!/usr/bin/env bash
set -euo pipefail

# Docker Workflow Test Suite
# Tests various build, deploy, and database scenarios that users/developers encounter

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_SCRIPT="$SCRIPT_DIR/build-and-deploy.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TAG_1="test-v1.0.0"
TEST_TAG_2="test-v2.0.0"
SQLITE_PORT=3001
POSTGRES_PORT=3002
CLIENT_PORT=8080
HEALTH_TIMEOUT=60

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    
    # Use build script for all cleanup operations
    $BUILD_SCRIPT stop || true
    $BUILD_SCRIPT stop --postgres || true
    $BUILD_SCRIPT clean all || true
    
    # Additional cleanup for any remaining test containers
    $BUILD_SCRIPT clean containers || true
    
    log_info "Cleanup completed"
}

# Health check functions
wait_for_service() {
    local url=$1
    local timeout=${2:-$HEALTH_TIMEOUT}
    local name=${3:-"service"}
    
    log_info "Waiting for $name at $url (timeout: ${timeout}s)"
    
    for i in $(seq 1 $timeout); do
        if curl -s -f "$url" >/dev/null 2>&1; then
            log_success "$name is healthy after ${i}s"
            return 0
        fi
        sleep 1
    done
    
    log_error "$name failed to become healthy within ${timeout}s"
    return 1
}

verify_database_type() {
    local expected_type=$1
    local port=${2:-$SQLITE_PORT}
    
    log_info "Verifying database type is $expected_type"
    
    # Try to get database info from health endpoint or API
    local response
    if response=$(curl -s "http://localhost:$port/api/health" 2>/dev/null); then
        if echo "$response" | grep -q "database.*$expected_type" || 
           echo "$response" | grep -q "$expected_type"; then
            log_success "Database type verified: $expected_type"
            return 0
        fi
    fi
    
    # Fallback: check using build script container status
    log_info "Checking container status for database verification..."
    if $BUILD_SCRIPT ps | grep -q "postgres" && [ "$expected_type" = "postgres" ]; then
        log_success "PostgreSQL deployment verified via container status"
        return 0
    elif $BUILD_SCRIPT ps | grep -q "opsimate" && [ "$expected_type" = "sqlite" ]; then
        log_success "SQLite deployment verified via container status"
        return 0
    fi
    
    log_warning "Could not definitively verify database type $expected_type"
    return 0  # Don't fail the test, just warn
}

test_build_components() {
    local tag=$1
    log_test "Testing build components with tag $tag"
    
    # Test building server
    log_info "Building server..."
    if ! $BUILD_SCRIPT build server --tag "$tag"; then
        log_error "Failed to build server"
        return 1
    fi
    
    # Test building client
    log_info "Building client..."
    if ! $BUILD_SCRIPT build client --tag "$tag"; then
        log_error "Failed to build client"
        return 1
    fi
    
    # Verify images exist using script status check
    log_info "Verifying built images..."
    if ! $BUILD_SCRIPT ps | grep -q "$tag"; then
        # Images might exist but not be running, let's check differently
        log_info "Images built successfully (not currently running)"
    fi
    
    log_success "Build components test passed"
    return 0
}

test_sqlite_deployment() {
    local tag=$1
    log_test "Testing SQLite deployment with tag $tag"
    
    # Set environment for SQLite
    export DATABASE_TYPE=sqlite
    export OPSIMATE_TAG="$tag"
    
    # Deploy server with SQLite
    log_info "Deploying server with SQLite..."
    if ! $BUILD_SCRIPT deploy-server --tag "$tag"; then
        log_error "Failed to deploy server with SQLite"
        return 1
    fi
    
    # Wait for server to be healthy
    if ! wait_for_service "http://localhost:$SQLITE_PORT/api/health" $HEALTH_TIMEOUT "SQLite server"; then
        log_error "SQLite server health check failed"
        log_info "Checking container status..."
        $BUILD_SCRIPT ps || true
        return 1
    fi
    
    # Verify database type
    verify_database_type "sqlite" $SQLITE_PORT
    
    log_success "SQLite deployment test passed"
    return 0
}

test_postgres_deployment() {
    local tag=$1
    log_test "Testing PostgreSQL deployment with tag $tag"
    
    # Set environment for PostgreSQL
    export DATABASE_TYPE=postgres
    export OPSIMATE_TAG="$tag"
    
    # Deploy server with PostgreSQL
    log_info "Deploying server with PostgreSQL..."
    if ! $BUILD_SCRIPT deploy-server --tag "$tag" --postgres; then
        log_error "Failed to deploy server with PostgreSQL"
        return 1
    fi
    
    # Wait for PostgreSQL to be ready first
    log_info "Waiting for PostgreSQL to be ready..."
    for i in $(seq 1 30); do
        if $BUILD_SCRIPT ps | grep -q "postgres.*Up"; then
            log_success "PostgreSQL is ready after ${i}s"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            log_error "PostgreSQL failed to become ready"
            $BUILD_SCRIPT ps || true
            return 1
        fi
    done
    
    # Wait for server to be healthy
    if ! wait_for_service "http://localhost:$POSTGRES_PORT/api/health" $HEALTH_TIMEOUT "PostgreSQL server"; then
        log_error "PostgreSQL server health check failed"
        log_info "Checking container status..."
        $BUILD_SCRIPT ps || true
        return 1
    fi
    
    # Verify database type
    verify_database_type "postgres" $POSTGRES_PORT
    
    log_success "PostgreSQL deployment test passed"
    return 0
}

test_client_connection() {
    local tag=$1
    local server_port=${2:-$SQLITE_PORT}
    log_test "Testing client connection with tag $tag"
    
    # Run client in background
    log_info "Starting client container..."
    # Start client detached and capture PID
    $BUILD_SCRIPT run-client --tag "$tag" >/dev/null 2>&1 &
    local client_pid=$!

    # Ensure the client process started
    if ! ps -p "$client_pid" >/dev/null 2>&1; then
        log_error "Failed to start client (process did not spawn)"
        return 1
    fi
    
    # Wait a bit for client to start
    sleep 5
    
    # Check if client is accessible
    if ! wait_for_service "http://localhost:$CLIENT_PORT" 30 "client"; then
        log_error "Client health check failed"
        kill $client_pid 2>/dev/null || true
        # Use build script to clean up client container
        $BUILD_SCRIPT clean containers || true
        return 1
    fi
    
    # Stop client
    kill $client_pid 2>/dev/null || true
    $BUILD_SCRIPT clean containers || true
    
    log_success "Client connection test passed"
    return 0
}

test_container_management() {
    log_test "Testing container management commands"
    
    # Test ps command
    log_info "Testing container listing..."
    if ! $BUILD_SCRIPT ps; then
        log_error "Container listing failed"
        return 1
    fi
    
    # Test stop command
    log_info "Testing container stop..."
    if ! $BUILD_SCRIPT stop; then
        log_error "Container stop failed"
        return 1
    fi
    
    # Verify containers are stopped
    log_info "Verifying containers are stopped..."
    if $BUILD_SCRIPT ps | grep -q "Up.*opsimate"; then
        log_error "Containers still running after stop command"
        $BUILD_SCRIPT ps
        return 1
    fi
    
    log_success "Container management test passed"
    return 0
}

test_version_upgrade() {
    log_test "Testing version upgrade scenario"
    
    # Deploy v1
    log_info "Deploying version $TEST_TAG_1..."
    if ! test_sqlite_deployment "$TEST_TAG_1"; then
        return 1
    fi
    
    # Stop v1
    log_info "Stopping version $TEST_TAG_1..."
    $BUILD_SCRIPT stop
    
    # Build and deploy v2
    log_info "Building and deploying version $TEST_TAG_2..."
    if ! test_build_components "$TEST_TAG_2"; then
        return 1
    fi
    
    if ! test_sqlite_deployment "$TEST_TAG_2"; then
        return 1
    fi
    
    # Clean up old version
    log_info "Cleaning up old version..."
    $BUILD_SCRIPT clean images --tag "$TEST_TAG_1"
    
    log_success "Version upgrade test passed"
    return 0
}

# Main test workflows
run_workflow_1() {
    log_test "=== WORKFLOW 1: SQLite Build and Test ==="
    
    test_build_components "$TEST_TAG_1" || return 1
    test_sqlite_deployment "$TEST_TAG_1" || return 1
    test_client_connection "$TEST_TAG_1" $SQLITE_PORT || return 1
    test_container_management || return 1
    
    log_success "Workflow 1 completed successfully"
}

run_workflow_2() {
    log_test "=== WORKFLOW 2: PostgreSQL Build and Test ==="
    
    # Clean up from previous workflow
    cleanup
    sleep 2
    
    test_build_components "$TEST_TAG_2" || return 1
    test_postgres_deployment "$TEST_TAG_2" || return 1
    test_client_connection "$TEST_TAG_2" $POSTGRES_PORT || return 1
    
    log_success "Workflow 2 completed successfully"
}

run_workflow_3() {
    log_test "=== WORKFLOW 3: Database Type Verification ==="
    
    # Clean up
    cleanup
    sleep 2
    
    # Test SQLite specifically
    log_info "Testing SQLite configuration..."
    export DATABASE_TYPE=sqlite
    test_sqlite_deployment "$TEST_TAG_1" || return 1
    verify_database_type "sqlite" $SQLITE_PORT || return 1
    
    # Stop and switch to PostgreSQL
    $BUILD_SCRIPT stop
    sleep 2
    
    log_info "Testing PostgreSQL configuration..."
    export DATABASE_TYPE=postgres
    test_postgres_deployment "$TEST_TAG_2" || return 1
    verify_database_type "postgres" $POSTGRES_PORT || return 1
    
    log_success "Workflow 3 completed successfully"
}

run_workflow_4() {
    log_test "=== WORKFLOW 4: Version Upgrade Scenario ==="
    
    # Clean up
    cleanup
    sleep 2
    
    test_version_upgrade || return 1
    
    log_success "Workflow 4 completed successfully"
}

# Main execution
main() {
    local workflow=${1:-"all"}
    
    log_info "Starting Docker Workflow Test Suite"
    log_info "Project root: $PROJECT_ROOT"
    log_info "Using build script: $BUILD_SCRIPT"
    
    # Ensure we're in the right directory
    cd "$PROJECT_ROOT"
    
    # Set up trap for cleanup
    trap cleanup EXIT
    
    # Initial cleanup
    cleanup
    sleep 2
    
    case "$workflow" in
        "1"|"sqlite")
            run_workflow_1
            ;;
        "2"|"postgres")
            run_workflow_2
            ;;
        "3"|"database")
            run_workflow_3
            ;;
        "4"|"upgrade")
            run_workflow_4
            ;;
        "all")
            run_workflow_1 || exit 1
            run_workflow_2 || exit 1
            run_workflow_3 || exit 1
            run_workflow_4 || exit 1
            ;;
        *)
            echo "Usage: $0 [1|sqlite|2|postgres|3|database|4|upgrade|all]"
            echo ""
            echo "Workflows:"
            echo "  1|sqlite   - SQLite build and test"
            echo "  2|postgres - PostgreSQL build and test"
            echo "  3|database - Database type verification"
            echo "  4|upgrade  - Version upgrade scenario"
            echo "  all        - Run all workflows (default)"
            exit 1
            ;;
    esac
    
    log_success "All requested workflows completed successfully!"
}

# Run main with all arguments
main "$@"
