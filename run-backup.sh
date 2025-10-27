#!/bin/bash

set -euo pipefail

# Neo4j Backup Script
# This script runs the Neo4j backup utility in a Docker container
# Usage: ./run-backup.sh [config_file]
#   config_file: Path to backup configuration file (default: ./backup.env)

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/backup.env}"

# Resolve to absolute path if relative path is provided
if [[ ! "$CONFIG_FILE" = /* ]]; then
    CONFIG_FILE="${SCRIPT_DIR}/${CONFIG_FILE}"
fi

# Source the configuration file
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Configuration file not found: ${CONFIG_FILE}"
    echo "Usage: ./run-backup.sh [config_file]"
    echo "Example: ./run-backup.sh backup.env.local"
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

# ============================================================================
# Validation
# ============================================================================

# Required variables
REQUIRED_VARS=(
    "DATABASE_BACKUP_ENDPOINTS"
    "DATABASE_NAME"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Required variable ${var} is not set in ${CONFIG_FILE}"
        exit 1
    fi
done

# ============================================================================
# Setup
# ============================================================================

# Set defaults
BACKUP_IMAGE="${BACKUP_IMAGE:-neo4j/helm-charts-backup:latest}"
TEMP_BACKUP_DIR="${TEMP_BACKUP_DIR:-/tmp/neo4j-backup}"
CONTAINER_NAME="${CONTAINER_NAME:-neo4j-backup-job}"

# Create temporary backup directory
mkdir -p "${TEMP_BACKUP_DIR}"

# ============================================================================
# Docker Environment Variables
# ============================================================================

DOCKER_ENV_ARGS=(
    -e "DATABASE=${DATABASE_NAME}"
    -e "DATABASE_BACKUP_ENDPOINTS=${DATABASE_BACKUP_ENDPOINTS}"
    -e "INCLUDE_METADATA=${INCLUDE_METADATA:-all}"
    -e "TYPE=${TYPE:-AUTO}"
    -e "KEEP_FAILED=${KEEP_FAILED:-false}"
    -e "COMPRESS=${COMPRESS:-true}"
    -e "VERBOSE=${VERBOSE:-true}"
    -e "PARALLEL_RECOVERY=${PARALLEL_RECOVERY:-false}"
    -e "PREFER_DIFF_AS_PARENT=${PREFER_DIFF_AS_PARENT:-false}"
)

# Add optional parameters if set
if [[ -n "${PAGE_CACHE:-}" ]]; then
    DOCKER_ENV_ARGS+=(-e "PAGE_CACHE=${PAGE_CACHE}")
fi

if [[ -n "${HEAP_SIZE:-}" ]]; then
    DOCKER_ENV_ARGS+=(-e "HEAP_SIZE=${HEAP_SIZE}")
fi

if [[ -n "${BACKUP_TEMP_DIR:-}" ]]; then
    DOCKER_ENV_ARGS+=(-e "BACKUP_TEMP_DIR=${BACKUP_TEMP_DIR}")
fi

# Cloud provider configuration
if [[ -n "${CLOUD_PROVIDER:-}" ]]; then
    DOCKER_ENV_ARGS+=(-e "CLOUD_PROVIDER=${CLOUD_PROVIDER}")
    DOCKER_ENV_ARGS+=(-e "BUCKET=${BUCKET_NAME}")
fi

# AWS-specific configuration
if [[ "${CLOUD_PROVIDER:-}" == "aws" ]]; then
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}")
    fi
    if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}")
    fi
    if [[ -n "${AWS_REGION:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "AWS_REGION=${AWS_REGION}")
    fi
    if [[ -n "${S3_ENDPOINT:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "S3_ENDPOINT=${S3_ENDPOINT}")
    fi
    if [[ -n "${S3_FORCE_PATH_STYLE:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "S3_FORCE_PATH_STYLE=${S3_FORCE_PATH_STYLE}")
    fi
    if [[ -n "${S3_SIGNATURE_VERSION:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "S3_SIGNATURE_VERSION=${S3_SIGNATURE_VERSION}")
    fi
    if [[ -n "${S3_CA_CERT_PATH:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "S3_CA_CERT_PATH=${S3_CA_CERT_PATH}")
    fi
    if [[ -n "${S3_SKIP_VERIFY:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "S3_SKIP_VERIFY=${S3_SKIP_VERIFY}")
    fi
fi

# GCP-specific configuration
if [[ "${CLOUD_PROVIDER:-}" == "gcp" ]]; then
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        if [[ ! -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
            echo "ERROR: GCP credentials file not found: ${GOOGLE_APPLICATION_CREDENTIALS}"
            exit 1
        fi
        DOCKER_ENV_ARGS+=(-v "${GOOGLE_APPLICATION_CREDENTIALS}:/credentials/gcp-key.json:ro")
        DOCKER_ENV_ARGS+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/credentials/gcp-key.json")
    fi
fi

# Azure-specific configuration
if [[ "${CLOUD_PROVIDER:-}" == "azure" ]]; then
    if [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}")
    fi
    if [[ -n "${AZURE_STORAGE_KEY:-}" ]]; then
        DOCKER_ENV_ARGS+=(-e "AZURE_STORAGE_KEY=${AZURE_STORAGE_KEY}")
    fi
fi

# ============================================================================
# Logging
# ============================================================================

LOG_FILE="${SCRIPT_DIR}/backup-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log "========================================"
log "Neo4j Backup Starting"
log "========================================"
log "Backup Endpoints: ${DATABASE_BACKUP_ENDPOINTS}"
log "Database(s): ${DATABASE_NAME}"
log "Cloud Provider: ${CLOUD_PROVIDER:-local}"
log "Bucket: ${BUCKET_NAME:-N/A}"
log "Temp Directory: ${TEMP_BACKUP_DIR}"
log "Docker Image: ${BACKUP_IMAGE}"
log "Log File: ${LOG_FILE}"
log "========================================"

# ============================================================================
# Docker Image Pull
# ============================================================================

log "Pulling Docker image: ${BACKUP_IMAGE}"
if ! docker pull "${BACKUP_IMAGE}" >> "${LOG_FILE}" 2>&1; then
    log "ERROR: Failed to pull Docker image"
    exit 1
fi

# ============================================================================
# Cleanup Previous Container
# ============================================================================

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "Removing previous container: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >> "${LOG_FILE}" 2>&1 || true
fi

# ============================================================================
# Run Backup
# ============================================================================

log "Starting backup container..."

if docker run \
    --name "${CONTAINER_NAME}" \
    --rm \
    --network "${DOCKER_NETWORK:-host}" \
    "${DOCKER_ENV_ARGS[@]}" \
    -v "${TEMP_BACKUP_DIR}:/backups:rw" \
    "${BACKUP_IMAGE}" >> "${LOG_FILE}" 2>&1; then

    log "========================================"
    log "Backup completed successfully!"
    log "========================================"

    # List backup files
    if [[ -d "${TEMP_BACKUP_DIR}" ]] && [[ -n "$(ls -A "${TEMP_BACKUP_DIR}" 2>/dev/null)" ]]; then
        log "Local backup files:"
        ls -lh "${TEMP_BACKUP_DIR}" | tee -a "${LOG_FILE}"
    fi

    exit 0
else
    log "========================================"
    log "ERROR: Backup failed!"
    log "========================================"
    log "Check the log file for details: ${LOG_FILE}"
    exit 1
fi
