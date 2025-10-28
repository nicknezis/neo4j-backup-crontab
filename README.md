# Neo4j Backup Script

A simple bash script solution for running Neo4j backups using the official Neo4j backup Docker container, designed to work outside of Kubernetes environments.

## Overview

This solution uses the same Neo4j backup utility that powers the Kubernetes Helm chart backups, but wraps it in a bash script that can be run directly via cron or manually. It supports:

- Backing up Neo4j databases to local storage and/or cloud providers (AWS S3, GCP, Azure)
- Multiple database backups in a single run
- Configurable backup behavior (consistency checks, fallback to full backups)
- Automatic logging and error handling

## Prerequisites

- Docker installed and running
- Network access to your Neo4j instance on the backup port (default: 6362)
- Neo4j must have backups enabled with `dbms.backup.enabled=true`
- For cloud backups: appropriate cloud credentials configured

## Quick Start

### 1. Setup Configuration

Copy the example configuration file and customize it:

```bash
cp backup.env.example backup.env
```

Edit `backup.env` and configure:

**Required settings:**
- `DATABASE_BACKUP_ENDPOINTS`: Neo4j backup endpoint(s) as host:port (comma-separated for clusters)
- `DATABASE_NAME`: Database(s) to backup (comma-separated)

**Optional settings:**
- `CLOUD_PROVIDER`: Set to `aws`, `gcp`, `azure`, or leave empty for local only
- `BUCKET_NAME`: Your cloud storage bucket name (required if using cloud provider)

**Single Instance Example:**
```bash
DATABASE_BACKUP_ENDPOINTS=neo4j.example.com:6362
DATABASE_NAME=neo4j,system
CLOUD_PROVIDER=aws
BUCKET_NAME=s3://my-neo4j-backups
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

**Cluster Example:**
```bash
DATABASE_BACKUP_ENDPOINTS=10.3.3.2:6362,10.3.3.3:6362,10.3.3.4:6362
DATABASE_NAME=neo4j,system
CLOUD_PROVIDER=aws
BUCKET_NAME=s3://my-neo4j-backups
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

### 2. Make Script Executable

```bash
chmod +x run-backup.sh
```

### 3. Run Backup Manually

```bash
./run-backup.sh
```

Or with a custom config file:
```bash
./run-backup.sh /path/to/custom-backup.env
```

The script will:
1. Validate configuration
2. Pull the Docker image if needed
3. Run the backup process
4. Store backups locally in `/tmp/neo4j-backup` (configurable)
5. Upload to cloud storage if configured
6. Generate a timestamped log file

### 4. Schedule with Cron

To run backups automatically, add to your crontab:

```bash
# Edit crontab
crontab -e

# Run backup daily at 2 AM
0 2 * * * /path/to/neo4j_backup/run-backup.sh

# Run backup every 6 hours
0 */6 * * * /path/to/neo4j_backup/run-backup.sh

# Run with custom config file
0 2 * * * /path/to/neo4j_backup/run-backup.sh /path/to/backup-prod.env
```

## Configuration Reference

### Neo4j Connection Settings

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `DATABASE_BACKUP_ENDPOINTS` | Backup endpoint(s) as host:port (comma-separated) | Yes | - |
| `DATABASE_NAME` | Database(s) to backup (comma-separated) | Yes | - |

Note: Authentication is handled internally by the Neo4j backup Docker image.

### Cloud Storage Settings

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `CLOUD_PROVIDER` | Cloud provider: `aws`, `gcp`, `azure` | No | - |
| `BUCKET_NAME` | Bucket/container name | If using cloud | - |

### AWS Configuration

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | If using AWS without IAM | - |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | If using AWS without IAM | - |
| `AWS_REGION` | AWS region | No | - |
| `S3_ENDPOINT` | Custom S3 endpoint (MinIO, etc.) | No | - |
| `S3_FORCE_PATH_STYLE` | Use path-style addressing | No | - |
| `S3_SIGNATURE_VERSION` | S3 signature version (2 or 4) | No | - |
| `S3_CA_CERT_PATH` | Custom CA certificate path | No | - |
| `S3_SKIP_VERIFY` | Skip SSL verification (not recommended) | No | - |

### Backup Behavior

| Variable | Description | Default |
|----------|-------------|---------|
| `INCLUDE_METADATA` | Metadata to include in backup | all |
| `TYPE` | Backup type (AUTO, FULL, DIFF) | AUTO |
| `KEEP_FAILED` | Keep failed backup attempts | false |
| `COMPRESS` | Compress backup files | true |
| `VERBOSE` | Detailed logging output | true |
| `PARALLEL_RECOVERY` | Parallel recovery during restore | false |
| `PREFER_DIFF_AS_PARENT` | Use differential backup as parent | false |
| `TEMP_BACKUP_DIR` | Local staging directory | /tmp/neo4j-backup |

### Optional Performance Tuning

| Variable | Description | Default |
|----------|-------------|---------|
| `PAGE_CACHE` | Neo4j page cache size (e.g., "2G") | - |
| `HEAP_SIZE` | JVM heap size (e.g., "4G") | - |
| `BACKUP_TEMP_DIR` | Temporary directory inside container | - |

### Docker Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKUP_IMAGE` | Docker image to use | neo4j/helm-charts-backup:latest |
| `CONTAINER_NAME` | Container name for the job | neo4j-backup-job |
| `DOCKER_NETWORK` | Docker network mode | host |

## Multiple Backup Jobs

To backup different Neo4j instances or databases with different schedules, create separate configuration files:

```bash
# Create specific configs for different instances
cp backup.env.example backup-prod.env
cp backup.env.example backup-dev.env

# Edit each config file for different instances
nano backup-prod.env
nano backup-dev.env
```

The script already accepts a config file path as the first argument, so you can use it directly in cron:

```bash
# Backup production database daily at 2 AM
0 2 * * * /path/to/run-backup.sh /path/to/backup-prod.env

# Backup dev database daily at 3 AM
0 3 * * * /path/to/run-backup.sh /path/to/backup-dev.env
```

## Backup Files

Backups are stored according to the Neo4j backup utility's naming convention. Local backups (if not uploaded to cloud) are temporarily stored in `TEMP_BACKUP_DIR` (default: `/tmp/neo4j-backup`).

When using cloud storage, backups are automatically uploaded to the specified bucket.

## Logs

Each backup run creates a timestamped log file in the script directory:

- Format: `backup-YYYYMMDD-HHMMSS.log`
- Contains detailed output from the backup process
- Useful for troubleshooting failures

## Troubleshooting

### Backup Port Not Accessible

**Error:** Connection refused to backup port

**Solution:**
1. Ensure Neo4j has backups enabled:
   ```
   dbms.backup.enabled=true
   dbms.backup.listen_address=0.0.0.0:6362
   ```
2. Check firewall rules allow the backup port
3. Verify network connectivity to each endpoint in `DATABASE_BACKUP_ENDPOINTS`:
   ```bash
   # Extract host and port from your endpoint
   nc -zv neo4j.example.com 6362
   ```
4. Confirm `DATABASE_BACKUP_ENDPOINTS` is correctly formatted (host:port)

### Cloud Upload Failed

**Error:** Cannot upload to cloud storage

**Solution:**
- Verify cloud credentials are correct
- Check bucket/container exists and is accessible
- For AWS: verify region is correct (if specified)
- Ensure `BUCKET_NAME` format matches the provider (e.g., `s3://bucket-name` for AWS)
- Check network connectivity to cloud provider
- Review the log file for detailed error messages

### Insufficient Disk Space

**Error:** No space left on device

**Solution:**
- Increase disk space on the machine
- Change `TEMP_BACKUP_DIR` to a location with more space
- Clean up old backup files regularly

### Docker Image Pull Failed

**Error:** Cannot pull image

**Solution:**
- Check Docker daemon is running: `docker ps`
- Verify internet connectivity
- Try pulling manually: `docker pull neo4j/helm-charts-backup:latest`

## Neo4j Backup Configuration

Your Neo4j instance must be configured to allow backups. Add these lines to `neo4j.conf`:

```
# Enable backup service
dbms.backup.enabled=true

# Listen on all interfaces (or specify specific IP)
dbms.backup.listen_address=0.0.0.0:6362

# Optional: Set backup directory
dbms.backup.backup_directory=/var/lib/neo4j/backups
```

Restart Neo4j after making configuration changes.

## Security Considerations

1. **Protect Configuration Files**: The `backup.env` file contains sensitive credentials
   ```bash
   chmod 600 backup.env
   ```

2. **Use IAM Roles**: For AWS deployments, consider using IAM instance roles instead of access keys

3. **Encrypt Backups**: Consider encrypting backups at rest and in transit

4. **Secure Network**: Ensure backup traffic is on a secure network or use TLS

5. **Rotate Credentials**: Regularly rotate Neo4j and cloud provider credentials

## Advanced Usage

### Custom S3-Compatible Storage (MinIO)

```bash
CLOUD_PROVIDER=aws
BUCKET_NAME=s3://neo4j-backups
S3_ENDPOINT=https://minio.example.com:9000
S3_FORCE_PATH_STYLE=true
AWS_ACCESS_KEY_ID=minio-access-key
AWS_SECRET_ACCESS_KEY=minio-secret-key
```

### Using AWS IAM Roles or Profiles

For AWS, instead of using static credentials, you can:

1. **IAM Instance Roles**: Remove `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from config. The Docker container will use the instance's IAM role.

2. **AWS Profiles**: Modify [run-backup.sh](run-backup.sh) to mount AWS credentials and specify profile:
   ```bash
   # Add to docker run command around line 194:
   -v "${HOME}/.aws:/root/.aws:ro" \
   -e "AWS_PROFILE=your-profile" \
   ```

### Monitoring and Alerting

Add monitoring by checking script exit code:

```bash
#!/bin/bash
# wrapper script for monitoring

if /path/to/run-backup.sh; then
    echo "Backup successful"
    # Send success notification
else
    echo "Backup failed"
    # Send alert (email, Slack, PagerDuty, etc.)
    curl -X POST https://hooks.slack.com/... -d '{"text":"Neo4j backup failed!"}'
fi
```

## References

- [Neo4j Helm Chart Backup Documentation](https://neo4j.com/labs/neo4j-helm/1.0.0/backup/)
- [Neo4j Admin Backup Helm Chart](https://github.com/neo4j/helm-charts/tree/dev/neo4j-admin)
- [Neo4j Backup Documentation](https://neo4j.com/docs/operations-manual/current/backup-restore/)

## License

This script is provided as-is for use with Neo4j backup operations.
