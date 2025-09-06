#!/usr/bin/env bash
set -euo pipefail

# Wrapper script to build and deploy Opsimate images
# Usage:
#   ./scripts/build-and-deploy.sh build [server|client|all] [--tag <tag>]
#   ./scripts/build-and-deploy.sh deploy-server [--tag <tag>] [--postgres]
#   ./scripts/build-and-deploy.sh run-client [--tag <tag>]
#   ./scripts/build-and-deploy.sh push [server|client|all] [--tag <tag>] [--registry my.registry/opsimate]
#   ./scripts/build-and-deploy.sh stop [--postgres]
#   ./scripts/build-and-deploy.sh clean [images|containers|all] [--tag <tag>]
#   ./scripts/build-and-deploy.sh ps

# Create .env from .env.example if it doesn't exist
if [ ! -f .env ] && [ -f .env.example ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo "Please edit .env with your specific configuration"
fi

# Load environment variables from .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    set -a
    source .env
    set +a
fi

ACTION=${1:-help}
TARGET=${2:-all}
shift || true
shift || true

TAG=""
REGISTRY=""
USE_POSTGRES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --registry) REGISTRY="$2"; shift 2;;
    --postgres) USE_POSTGRES=true; shift;;
    *) shift;;
  esac
done

# Use OPSIMATE_TAG from .env if no --tag provided
if [ -z "$TAG" ] && [ -n "${OPSIMATE_TAG:-}" ]; then
    TAG="$OPSIMATE_TAG"
fi

# If still no tag, derive from git or use default
if [ -z "$TAG" ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
    TAG="${BRANCH}-${SHA}"
    TAG=${TAG//\//-}
  else
    TAG="local-$(date +%Y%m%d%H%M%S)"
  fi
fi

FULL_REGISTRY_PREFIX=""
if [ -n "$REGISTRY" ]; then
  FULL_REGISTRY_PREFIX="${REGISTRY%/}/"
fi

BUILD_ARGS=(--progress=plain)

# Function to verify tag exists (for information only - NO local git operations)
prepare_source() {
    local tag=$1
    
    # Skip verification for local builds
    if [ "$tag" = "local" ]; then
        echo "Building from current local state..."
        return
    fi
    
    echo "Verifying tag '$tag' existence..."
    
    # Check if tag exists locally
    if git rev-parse --verify "$tag" >/dev/null 2>&1; then
        echo "Tag '$tag' found locally."
        return
    fi
    
    # Check current origin remote
    if git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/$tag"; then
        echo "Tag '$tag' found in current remote (origin)."
        return
    fi
    
    # Check official OpsiMate repository as fallback
    if git ls-remote --tags https://github.com/OpsiMate/OpsiMate.git 2>/dev/null | grep -q "refs/tags/$tag"; then
        echo "Tag '$tag' found in official OpsiMate repository."
        echo "Note: Building from current HEAD since we don't modify local git state."
        return
    fi
    
    echo "Warning: Tag '$tag' not found in any repository. Building from current HEAD."
}

build_server() {
  echo "Building server image: ${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}"
  prepare_source "$TAG"
  
  # Determine build args based on tag
  local build_args=("${BUILD_ARGS[@]}")
  if [ "$TAG" != "local" ]; then
    build_args+=(--build-arg "SOURCE_TAG=$TAG")
    echo "Building from git tag: $TAG"
  else
    build_args+=(--build-arg "SOURCE_TAG=local")
    echo "Building from local context"
  fi
  
  docker build "${build_args[@]}" --target server-runtime -f docker/Dockerfile -t "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}" .
}

build_client() {
  echo "Building client image: ${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}"
  prepare_source "$TAG"
  
  # Determine build args based on tag
  local build_args=("${BUILD_ARGS[@]}")
  if [ "$TAG" != "local" ]; then
    build_args+=(--build-arg "SOURCE_TAG=$TAG")
    echo "Building from git tag: $TAG"
  else
    build_args+=(--build-arg "SOURCE_TAG=local")
    echo "Building from local context"
  fi
  
  docker build "${build_args[@]}" --target client-runtime -t "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" .
}

push_image() {
  local image=$1
  echo "Pushing ${image}"
  docker push "${image}"
}

stop_containers() {
  echo "Checking running OpsiMate containers..."
  
  # Determine which compose file to use
  COMPOSE_FILE="docker/docker-compose.opsimate.server.yml"
  if [ "$USE_POSTGRES" = true ] || [ "${DATABASE_TYPE:-}" = "postgres" ]; then
      COMPOSE_FILE="docker/docker-compose.opsimate.postgres.yml"
      echo "Using PostgreSQL compose configuration"
  else
      echo "Using SQLite compose configuration"
  fi
  
  # Check if there are any OpsiMate containers running
  RUNNING_CONTAINERS=$(docker ps --filter "name=opsimate" --format "{{.Names}}" | wc -l)
  
  if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
    echo "Found $RUNNING_CONTAINERS running OpsiMate container(s):"
    docker ps --filter "name=opsimate" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "Stopping containers using compose file: $COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" down
  else
    echo "No OpsiMate containers are currently running."
    
    # Check for any containers with opsimate in the name anyway
    ALL_OPSIMATE=$(docker ps -a --filter "name=opsimate" --format "{{.Names}}" | wc -l)
    if [ "$ALL_OPSIMATE" -gt 0 ]; then
      echo "Found $ALL_OPSIMATE stopped OpsiMate container(s):"
      docker ps -a --filter "name=opsimate" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    fi
  fi
}

clean_resources() {
  local target=$1
  
  case "$target" in
    containers)
      echo "Cleaning OpsiMate containers..."
      # Remove all opsimate containers (running and stopped)
      CONTAINERS=$(docker ps -a --filter "name=opsimate" -q)
      if [ -n "$CONTAINERS" ]; then
        docker rm -f $CONTAINERS
        echo "Removed OpsiMate containers."
      else
        echo "No OpsiMate containers to remove."
      fi
      ;;
    images)
      echo "Cleaning OpsiMate images..."
      if [ -n "$TAG" ]; then
        # Remove specific tag
        echo "Removing images with tag: $TAG"
        docker rmi -f "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}" 2>/dev/null || echo "Server image with tag $TAG not found"
        docker rmi -f "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" 2>/dev/null || echo "Client image with tag $TAG not found"
      else
        # Remove all opsimate images
        IMAGES=$(docker images --filter "reference=*opsimate/*" -q)
        if [ -n "$IMAGES" ]; then
          docker rmi -f $IMAGES
          echo "Removed all OpsiMate images."
        else
          echo "No OpsiMate images to remove."
        fi
      fi
      ;;
    all)
      echo "Cleaning all OpsiMate resources..."
      clean_resources containers
      clean_resources images
      # Clean up any dangling images
      echo "Cleaning up dangling images..."
      docker image prune -f
      ;;
    *)
      echo "Unknown clean target: $target"
      echo "Available targets: containers, images, all"
      exit 1
      ;;
  esac
}

list_containers() {
  echo "=== OpsiMate Container Status ==="
  
  # Check running containers
  RUNNING=$(docker ps --filter "name=opsimate" --format "{{.Names}}" | wc -l)
  if [ "$RUNNING" -gt 0 ]; then
    echo "Running OpsiMate containers ($RUNNING):"
    docker ps --filter "name=opsimate" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    echo
  fi
  
  # Check all containers (including stopped)
  ALL=$(docker ps -a --filter "name=opsimate" --format "{{.Names}}" | wc -l)
  if [ "$ALL" -gt "$RUNNING" ]; then
    STOPPED=$((ALL - RUNNING))
    echo "Stopped OpsiMate containers ($STOPPED):"
    docker ps -a --filter "name=opsimate" --filter "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
    echo
  fi
  
  if [ "$ALL" -eq 0 ]; then
    echo "No OpsiMate containers found."
  fi
  
  # Show images
  echo "=== OpsiMate Images ==="
  IMAGES=$(docker images --filter "reference=*opsimate/*" --format "{{.Repository}}" | wc -l)
  if [ "$IMAGES" -gt 0 ]; then
    docker images --filter "reference=*opsimate/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
  else
    echo "No OpsiMate images found."
  fi
}

case "$ACTION" in
  build)
    case "$TARGET" in
      server) build_server ;;
      client) build_client ;;
      all) build_server; build_client ;;
      *) echo "Unknown build target: $TARGET"; exit 1 ;;
    esac
    ;;
  deploy-server)
    if ! docker image inspect "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}" >/dev/null 2>&1; then
      build_server
    fi
    export OPSIMATE_TAG="${TAG}"
    
    # Choose compose file based on postgres flag or environment
    COMPOSE_FILE="docker/docker-compose.opsimate.server.yml"
    if [ "$USE_POSTGRES" = true ] || [ "${DATABASE_TYPE:-}" = "postgres" ]; then
        COMPOSE_FILE="docker/docker-compose.opsimate.postgres.yml"
        echo "Using PostgreSQL compose configuration"
    else
        echo "Using SQLite compose configuration"
    fi
    
    OPSIMATE_TAG="${TAG}" docker compose -f "$COMPOSE_FILE" up -d
    ;;
  run-client)
    if ! docker image inspect "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" >/dev/null 2>&1; then
      build_client
    fi
    echo "Running client (will be removed on exit) - http://localhost:8080"
    docker run --rm -p 8080:8080 --name opsimate-client "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}"
    ;;
  stop)
    stop_containers
    ;;
  clean)
    TARGET=${TARGET:-all}
    clean_resources "$TARGET"
    ;;
  ps)
    list_containers
    ;;
  push)
    case "$TARGET" in
      server)
        push_image "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}" ;;
      client)
        push_image "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" ;;
      all)
        push_image "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}"
        push_image "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" ;;
      *)
        echo "Unknown push target: $TARGET"; exit 1 ;;
    esac
    ;;
  *)
    cat <<EOF
Usage:
  $0 build [server|client|all] [--tag <tag>]
  $0 deploy-server [--tag <tag>] [--postgres]
  $0 run-client [--tag <tag>]
  $0 push [server|client|all] [--tag <tag>] [--registry my.registry/opsimate]
  $0 stop [--postgres]
  $0 clean [containers|images|all] [--tag <tag>]
  $0 ps

Container Management:
  stop: Stop running OpsiMate containers using docker compose
  clean: Remove containers, images, or both
    - containers: Remove all OpsiMate containers (running and stopped)
    - images: Remove OpsiMate images (all or specific tag with --tag)
    - all: Remove containers and images, plus cleanup dangling images
  ps: List all OpsiMate containers and images with their status

Environment Configuration:
  Create .env file from .env.example to set default values.
  
  Key variables:
  - OPSIMATE_TAG: Default tag to use if --tag not specified
  - DATABASE_TYPE: 'sqlite' or 'postgres' (affects deploy-server)
  - POSTGRES_*: PostgreSQL connection details

Tag Handling:
  If --tag is omitted, uses OPSIMATE_TAG from .env, then <branch>-<sha>.
  If tag doesn't exist locally and is not 'local', attempts to fetch from git remote.

Examples:
  $0 build all --tag v0.0.28
  $0 deploy-server --tag v0.0.28 --postgres
  $0 deploy-server  # Uses .env configuration
  $0 stop --postgres
  $0 clean images --tag v0.0.28
  $0 clean all
  $0 ps
EOF
    ;;
esac
