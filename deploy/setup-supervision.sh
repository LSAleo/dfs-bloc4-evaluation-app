#!/usr/bin/env bash
#
# setup-supervision.sh — Installe la supervision OpsTrack :
#   - fail2ban : audit et blocage des tentatives d'intrusion (SSH + HTTP)
#   - logrotate : rotation des journaux applicatifs Laravel
#   - cron : sauvegarde quotidienne + sonde de sante toutes les 5 minutes
#
#   sudo bash deploy/setup-supervision.sh
#
set -euo pipefail
APP_DIR="${APP_DIR:-/var/www/opstrack}"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y fail2ban >/dev/null

# --- fail2ban : SSH + auth HTTP (des scans hostiles ont ete observes en logs) ---
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*error*.log

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/*access*.log
JAIL
systemctl enable --now fail2ban >/dev/null
systemctl restart fail2ban

# --- logrotate : journaux applicatifs Laravel ---
cat > /etc/logrotate.d/opstrack <<LOGR
${APP_DIR}/storage/logs/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su www-data www-data
}
LOGR

# --- taches planifiees ---
cat > /etc/cron.d/opstrack <<CRON
# Sauvegarde quotidienne a 03h00
0 3 * * * root BACKUP_DIR=/var/backups/opstrack bash ${APP_DIR}/deploy/backup.sh >> /var/log/opstrack-backup.log 2>&1
# Sonde de sante toutes les 5 minutes
*/5 * * * * ubuntu bash ${APP_DIR}/deploy/healthcheck.sh >> /var/log/opstrack-health.log 2>&1
CRON
chmod 644 /etc/cron.d/opstrack

echo "[ok] supervision installee (fail2ban, logrotate, cron)"
