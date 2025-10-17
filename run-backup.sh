#!/bin/bash

set -euo pipefail

# Neo4j Backup Script
# This script runs the Neo4j backup utility in a Docker container

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.env"

# Source the configuration file
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Configuration file not found: ${CONFIG_FILE}"
    echo "Please copy backup.env.example to backup.env and configure it."
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

# ============================================================================
# Validation
# ============================================================================

# Required variables
REQUIRED_VARS=(
    "NEO4J_HOST"
    "DATABASE_NAME"
    "NEO4J_USER"
    "NEO4J_PASSWORD"
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
NEO4J_BACKUP_PORT="${NEO4J_BACKUP_PORT:-6362}"
BACKUP_IMAGE="${BACKUP_IMAGE:-neo4j/helm-charts-backup:latest}"
TEMP_BACKUP_DIR="${TEMP_BACKUP_DIR:-/tmp/neo4j-backup}"
CONTAINER_NAME="${CONTAINER_NAME:-neo4j-backup-job}"
FALLBACK_TO_FULL="${FALLBACK_TO_FULL:-true}"
CHECK_CONSISTENCY="${CHECK_CONSISTENCY:-false}"
CHECK_INDEXES="${CHECK_INDEXES:-false}"
BACKUP_TIMEOUT="${BACKUP_TIMEOUT:-3600}"

# Create temporary backup directory
mkdir -p "${TEMP_BACKUP_DIR}"

# Construct Neo4j address
NEO4J_ADDR="${NEO4J_HOST}:${NEO4J_BACKUP_PORT}"

# ============================================================================
# Docker Environment Variables
# ============================================================================

DOCKER_ENV_ARGS=(
    -e "DATABASE=${DATABASE_NAME}"
    -e "NEO4J_ADDR=${NEO4J_ADDR}"
    -e "NEO4J_USER=${NEO4J_USER}"
    -e "NEO4J_PASSWORD=${NEO4J_PASSWORD}"
    -e "FALLBACK_TO_FULL=${FALLBACK_TO_FULL}"
    -e "CHECK_CONSISTENCY=${CHECK_CONSISTENCY}"
    -e "CHECK_INDEXES=${CHECK_INDEXES}"
    -e "NEO4J_server_config_strict__validation_enabled=false"
)

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
log "Neo4j Address: ${NEO4J_ADDR}"
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
    "${DOCKER_ENV_ARGS[@]}" \
    -v "${TEMP_BACKUP_DIR}:/data:rw" \
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
