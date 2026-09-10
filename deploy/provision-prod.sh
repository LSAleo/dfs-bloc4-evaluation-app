#!/usr/bin/env bash
#
# provision-prod.sh — Mise en service reproductible d'OpsTrack sur une machine
# Ubuntu 24.04 « nue » (Apache + PHP 8.4 + MySQL + MongoDB + Redis + Node).
#
# Idempotent : relançable sans casser un état déjà en place.
# Les secrets (mot de passe BDD, token API, secret webhook) sont GENERES sur la
# machine et écrits uniquement dans .env (chmod 640). Ils ne sont jamais affichés
# ni committés.
#
# Usage :
#   sudo DOMAIN=eval-dfs-p-tpl-20265-07.it-students.fr \
#        REPO=https://github.com/LSAleo/dfs-bloc4-evaluation-app.git \
#        bash provision-prod.sh
#
set -euo pipefail

DOMAIN="${DOMAIN:-eval-dfs-p-tpl-20265-07.it-students.fr}"
REPO="${REPO:-https://github.com/LSAleo/dfs-bloc4-evaluation-app.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-/var/www/opstrack}"
DB_NAME="${DB_NAME:-opstrack}"
DB_USER="${DB_USER:-opstrack}"
MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD:-0000}"   # a durcir hors epreuve

echo "==> [1/9] Paquets systeme"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  apache2 libapache2-mod-php8.4 php8.4-cli php8.4-mysql php8.4-mongodb \
  php8.4-redis php8.4-mbstring php8.4-xml php8.4-curl php8.4-zip php8.4-bcmath php8.4-intl \
  mysql-server mongodb-org redis-server nodejs npm composer git curl \
  certbot python3-certbot-apache >/dev/null

echo "==> [2/9] Recuperation du code (${BRANCH})"
if [ ! -d "${APP_DIR}/.git" ]; then
  git clone --branch "${BRANCH}" "${REPO}" /tmp/opstrack-src
  mkdir -p "${APP_DIR}"; shopt -s dotglob; mv /tmp/opstrack-src/* "${APP_DIR}/"; rmdir /tmp/opstrack-src
else
  git -C "${APP_DIR}" fetch --all -q && git -C "${APP_DIR}" reset --hard "origin/${BRANCH}"
fi
cd "${APP_DIR}"

echo "==> [3/9] Dependances PHP (prod)"
# NB: l'extension systeme ext-mongodb (2.1.4) est anterieure a la contrainte du
# lock (mongodb/mongodb 2.2.0 -> ext-mongodb ^2.2). L'ecart est sans effet
# fonctionnel ici (journalisation Mongo tolerante aux pannes) ; on l'ignore au
# niveau plateforme, comme sur la qualification. Cible : image conteneur avec
# ext-mongodb >= 2.2 (cf. 01_architecture_hebergement.md).
sudo -u "$SUDO_USER" composer install --no-dev --optimize-autoloader --no-interaction \
  --ignore-platform-req=ext-mongodb

echo "==> [4/9] Base de donnees + utilisateur applicatif (moindre privilege)"
DB_PASS="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 28)"
mysql -uroot -p"${MYSQL_ROOT_PWD}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> [5/9] Fichier .env de production"
if [ ! -f .env ]; then cp .env.example .env; fi
API_TOKEN="$(openssl rand -hex 32)"
HOOK_PASS="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 28)"
set_env() { sed -i "s|^$1=.*|$1=$2|" .env; }
set_env APP_ENV production
set_env APP_DEBUG false
set_env APP_URL "https://${DOMAIN}"
set_env APP_LOCALE fr
set_env DB_DATABASE "${DB_NAME}"
set_env DB_USERNAME "${DB_USER}"
set_env DB_PASSWORD "${DB_PASS}"
set_env OPSTRACK_API_TOKEN "${API_TOKEN}"
set_env WEBHOOK_BASIC_USER opstrack-hook
set_env WEBHOOK_BASIC_PASSWORD "${HOOK_PASS}"
# .env lisible par www-data (Apache/mod_php) mais pas par le reste du monde
chown "$SUDO_USER":www-data .env && chmod 640 .env
sudo -u "$SUDO_USER" php artisan key:generate --force

echo "==> [6/9] Schema + donnees + droits"
sudo -u "$SUDO_USER" php artisan migrate --force --seed
chown -R "$SUDO_USER":www-data "${APP_DIR}"
find storage bootstrap/cache -type d -exec chmod 2775 {} \;
find storage bootstrap/cache -type f -exec chmod 664 {} \;
sudo -u "$SUDO_USER" php artisan config:clear

echo "==> [7/9] Apache (vhost + modules)"
tee /etc/apache2/sites-available/opstrack.conf >/dev/null <<VH
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${APP_DIR}/public
    <Directory ${APP_DIR}/public>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>
    ProxyPreserveHost On
    ProxyPass        /dispatch-dashboard http://127.0.0.1:3000/
    ProxyPassReverse /dispatch-dashboard http://127.0.0.1:3000/
    ErrorLog  \${APACHE_LOG_DIR}/opstrack_error.log
    CustomLog \${APACHE_LOG_DIR}/opstrack_access.log combined
</VirtualHost>
VH
a2enmod rewrite proxy proxy_http headers ssl >/dev/null
a2ensite opstrack >/dev/null; a2dissite 000-default >/dev/null 2>&1 || true
apache2ctl configtest
systemctl reload apache2

echo "==> [8/9] Microservice Next.js (build + service systemd)"
MS="${APP_DIR}/microservices/dispatch-dashboard"
grep -q "${DOMAIN}" /etc/hosts || echo "127.0.0.1 ${DOMAIN}" >> /etc/hosts  # loopback, evite le hairpin NAT
cat > "${MS}/.env.local" <<ENVL
LARAVEL_API_BASE_URL=https://${DOMAIN}/api/v1
LARAVEL_API_TOKEN=${API_TOKEN}
ENVL
chown "$SUDO_USER":www-data "${MS}/.env.local"; chmod 640 "${MS}/.env.local"
sudo -u "$SUDO_USER" bash -c "cd '${MS}' && npm install --no-audit --no-fund && npm run build"
tee /etc/systemd/system/opstrack-dispatch-dashboard.service >/dev/null <<UNIT
[Unit]
Description=OpsTrack Dispatch Dashboard
After=network.target
[Service]
Type=simple
User=${SUDO_USER}
WorkingDirectory=${MS}
Environment=NODE_ENV=production
EnvironmentFile=${MS}/.env.local
ExecStart=/usr/bin/npm run start -- --hostname 127.0.0.1 --port 3000
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now opstrack-dispatch-dashboard

echo "==> [9/9] HTTPS (Let's Encrypt) + pare-feu"
certbot --apache -d "${DOMAIN}" --non-interactive --agree-tos \
  --register-unsafely-without-email --redirect
ufw allow OpenSSH >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

echo "==> Termine. Smoke test :"
curl -s -o /dev/null -w "  https://${DOMAIN}/            -> %{http_code}\n" "https://${DOMAIN}/"
curl -s -o /dev/null -w "  https://${DOMAIN}/api/health  -> %{http_code}\n" "https://${DOMAIN}/api/health"
curl -s -o /dev/null -w "  https://${DOMAIN}/dispatch-dashboard -> %{http_code}\n" "https://${DOMAIN}/dispatch-dashboard"
