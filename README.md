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
- `NEO4J_HOST`: Your Neo4j server hostname or IP
- `DATABASE_NAME`: Database(s) to backup (comma-separated)
- `NEO4J_USER`: Neo4j username
- `NEO4J_PASSWORD`: Neo4j password
- `CLOUD_PROVIDER`: Set to `aws`, `gcp`, `azure`, or leave empty for local only
- `BUCKET_NAME`: Your cloud storage bucket name

**AWS Example:**
```bash
NEO4J_HOST=neo4j.example.com
DATABASE_NAME=neo4j,system
NEO4J_USER=neo4j
NEO4J_PASSWORD=your-password
CLOUD_PROVIDER=aws
BUCKET_NAME=s3://my-neo4j-backups
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
```

### 2. Run Backup Manually

```bash
./run-backup.sh
```

The script will:
1. Validate configuration
2. Pull the Docker image if needed
3. Run the backup process
4. Store backups locally in `/tmp/neo4j-backup` (configurable)
5. Upload to cloud storage if configured
6. Generate a timestamped log file

### 3. Schedule with Cron

To run backups automatically, add to your crontab:

```bash
# Edit crontab
crontab -e

# Run backup daily at 2 AM
0 2 * * * /path/to/neo4j_backup/run-backup.sh

# Run backup every 6 hours
0 */6 * * * /path/to/neo4j_backup/run-backup.sh
```

## Configuration Reference

### Neo4j Connection Settings

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `NEO4J_HOST` | Neo4j server hostname/IP | Yes | - |
| `NEO4J_BACKUP_PORT` | Backup port | No | 6362 |
| `DATABASE_NAME` | Database(s) to backup | Yes | - |
| `NEO4J_USER` | Neo4j username | Yes | - |
| `NEO4J_PASSWORD` | Neo4j password | Yes | - |

### Cloud Storage Settings

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `CLOUD_PROVIDER` | Cloud provider: `aws`, `gcp`, `azure` | No | - |
| `BUCKET_NAME` | Bucket/container name | If using cloud | - |

### AWS Configuration

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | If using AWS | - |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | If using AWS | - |
| `AWS_REGION` | AWS region | No | us-east-1 |
| `S3_ENDPOINT` | Custom S3 endpoint (MinIO, etc.) | No | - |
| `S3_FORCE_PATH_STYLE` | Use path-style addressing | No | true |
| `S3_SIGNATURE_VERSION` | S3 signature version (2 or 4) | No | 4 |

### Backup Behavior

| Variable | Description | Default |
|----------|-------------|---------|
| `FALLBACK_TO_FULL` | Fallback to full backup if incremental fails | true |
| `CHECK_CONSISTENCY` | Run consistency check after backup | false |
| `CHECK_INDEXES` | Check indexes after backup | false |
| `TEMP_BACKUP_DIR` | Local staging directory | /tmp/neo4j-backup |
| `BACKUP_TIMEOUT` | Timeout in seconds | 3600 |

### Docker Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `BACKUP_IMAGE` | Docker image to use | neo4j/helm-charts-backup:latest |
| `CONTAINER_NAME` | Container name for the job | neo4j-backup-job |

## Multiple Backup Jobs

To backup different Neo4j instances or databases with different schedules, create separate configuration files:

```bash
# Copy the script and create specific configs
cp backup.env.example backup-prod.env
cp backup.env.example backup-dev.env

# Edit each config file for different instances
# Then create a wrapper script or modify run-backup.sh to accept config path as argument
```

**Example: Modified script to accept config file parameter:**

```bash
# Add this near the top of run-backup.sh after SCRIPT_DIR
CONFIG_FILE="${1:-${SCRIPT_DIR}/backup.env}"
```

Then use in cron:

```bash
# Backup production database daily at 2 AM
0 2 * * * /path/to/run-backup.sh /path/to/backup-prod.env

# Backup dev database daily at 3 AM
0 3 * * * /path/to/run-backup.sh /path/to/backup-dev.env
```

## Backup Files

Backups are stored with timestamps:

- Format: `{database}-{timestamp}.tar.gz`
- Example: `neo4j-2025-01-15T14-30-00.tar.gz`
- A `latest` copy is also created for easy access

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
2. Check firewall rules allow port 6362
3. Verify network connectivity: `nc -zv <NEO4J_HOST> 6362`

### Authentication Failed

**Error:** Authentication error

**Solution:**
- Verify `NEO4J_USER` and `NEO4J_PASSWORD` are correct
- Ensure the user has backup privileges

### Cloud Upload Failed

**Error:** Cannot upload to S3/GCS/Azure

**Solution:**
- Verify cloud credentials are correct
- Check bucket/container exists and is accessible
- For AWS: verify region is correct
- Check network connectivity to cloud provider

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

### Using AWS Profile Instead of Keys

Remove `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from config, then mount AWS credentials:

```bash
# Modify run-backup.sh to add:
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
