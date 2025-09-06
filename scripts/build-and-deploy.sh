#!/usr/bin/env bash
set -euo pipefail

# Wrapper script to build and deploy Opsimate images
# Usage:
#   ./scripts/build-and-deploy.sh build [server|client|all] [--tag <tag>]
#   ./scripts/build-and-deploy.sh deploy-server [--tag <tag>] [--postgres]
#   ./scripts/build-and-deploy.sh run-client [--tag <tag>]
#   ./scripts/build-and-deploy.sh push [server|client|all] [--tag <tag>] [--registry my.registry/opsimate]

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

# Function to clone and checkout specific tag if needed
prepare_source() {
    local tag=$1
    
    # If tag is not "local" and doesn't exist locally, try to fetch it
    if [ "$tag" != "local" ] && ! git rev-parse --verify "$tag" >/dev/null 2>&1; then
        echo "Tag '$tag' not found locally. Fetching from remote..."
        if git ls-remote --tags origin | grep -q "refs/tags/$tag"; then
            git fetch --tags
            if git rev-parse --verify "$tag" >/dev/null 2>&1; then
                echo "Checking out tag '$tag'..."
                git checkout "$tag"
            else
                echo "Warning: Tag '$tag' not found in remote. Building from current HEAD."
            fi
        else
            echo "Warning: Tag '$tag' not found in remote. Building from current HEAD."
        fi
    elif [ "$tag" != "local" ]; then
        echo "Checking out tag '$tag'..."
        git checkout "$tag"
    fi
}

build_server() {
  echo "Building server image: ${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}"
  prepare_source "$TAG"
  docker build "${BUILD_ARGS[@]}" --target server-runtime -t "${FULL_REGISTRY_PREFIX}opsimate/server:${TAG}" .
}

build_client() {
  echo "Building client image: ${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}"
  prepare_source "$TAG"
  docker build "${BUILD_ARGS[@]}" --target client-runtime -t "${FULL_REGISTRY_PREFIX}opsimate/client:${TAG}" .
}

push_image() {
  local image=$1
  echo "Pushing ${image}"
  docker push "${image}"
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
EOF
    ;;
esac
