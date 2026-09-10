# Base de connaissances — Note de passation

Document destine a un pair reprenant la maintenance d'OpsTrack. Objectif : comprendre le fonctionnement, les points d'attention et les procedures essentielles sans zone d'ombre.

## 1. Presentation de l'application

**OpsTrack Field Service** gere des interventions terrain : tickets, interventions, techniciens, sites clients. Utilisateurs : superviseurs (tableau de bord) et techniciens. Un microservice affiche un tableau de bord de dispatch ; un webhook injecte des evenements externes ; une API publique (Open-Meteo) enrichit les sites.

## 2. Architecture technique

- **Laravel 12 / PHP 8.4** : front web + API REST `/api/v1` + webhook `public/hooks.php`.
- **MySQL** : donnees metier. **MongoDB** : journaux (`app_events`). **Redis** : cache/sessions (cible).
- **Next.js** : microservice `dispatch-dashboard` (systemd, `127.0.0.1:3000`, proxy `/dispatch-dashboard`).
- **Apache** : sert `public/` et proxifie le microservice ; **HTTPS** via Let's Encrypt.

Details du code : `documentation_technique/`. Architecture cible (montee en charge) : `../01_architecture_hebergement.md`.

## 3. Environnements et acces

| Environnement | URL | Machine |
| --- | --- | --- |
| Qualification | `http://eval-dfs-q-tpl-20265-07.it-students.fr` | `13.38.229.32` |
| Production | `https://eval-dfs-p-tpl-20265-07.it-students.fr` | `15.188.48.193` |

- Acces SSH : `ssh -i ubuntu.pem ubuntu@<hote>` (authentification par cle uniquement).
- Code deploye : `/var/www/opstrack`. Secrets : `/var/www/opstrack/.env` (`640`, `ubuntu:www-data`, **non versionne**).
- Depot : `https://github.com/LSAleo/dfs-bloc4-evaluation-app` (fork).

## 4. Procedure de deploiement

- **Provisioning initial** (machine nue) : `sudo bash deploy/provision-prod.sh`.
- **Mise a jour** : pipeline CI/CD (`.github/workflows/deploy.yml`, deux paliers qualification -> production) **ou** manuellement :
  ```bash
  ssh -i ubuntu.pem ubuntu@<hote> 'bash /var/www/opstrack/deploy/update-prod.sh main'
  ```
- Le deploiement execute : `git reset --hard origin/<ref>`, `composer install --no-dev`, `migrate --force`, build du microservice, redemarrage, **smoke test** et **rollback automatique** en cas d'echec.
- Details et conduite en cas d'echec : `../03_deploiement_ci_cd.md`.

## 5. Supervision et exploitation

- **Sonde** : `deploy/healthcheck.sh` (cron `*/5`) — services, `/api/health`, disque, expiration TLS ; anomalies dans syslog (`opstrack-health`) et `/var/log/opstrack-health.log`.
- **Journaux** :
  - Application : `/var/www/opstrack/storage/logs/laravel.log`
  - Apache : `/var/log/apache2/opstrack_{access,error}.log`
  - Microservice : `journalctl -u opstrack-dispatch-dashboard`
  - Metier : MongoDB `opstrack_logs.app_events`
- **fail2ban** : `sudo fail2ban-client status` (jails `sshd`, `apache-auth`, `apache-badbots`).
- **Redemarrer un service** : `sudo systemctl restart {apache2|opstrack-dispatch-dashboard|mysql|mongod|redis-server}`.

## 6. Sauvegarde et reprise

- **Sauvegarde** : `deploy/backup.sh` (cron quotidien 03h00) -> `/var/backups/opstrack/<horodatage>/` (MySQL + MongoDB + `.env`), retention 7 jours.
- **Restauration** :
  ```bash
  gunzip < /var/backups/opstrack/<stamp>/mysql-opstrack.sql.gz | mysql -u<user> -p opstrack
  mongorestore --gzip --archive=/var/backups/opstrack/<stamp>/mongo-opstrack_logs.archive.gz
  php artisan config:clear
  ```
- Procedure validee sur base temporaire (cf. `../04_supervision_maintien.md`).

## 7. Points d'attention (pieges connus)

- **`ext-mongodb`** : la version systeme (2.1.4) est anterieure a la contrainte du `composer.lock` (2.2.0). Les installations utilisent `--ignore-platform-req=ext-mongodb` (comme en qualification). Cible : image conteneur avec `ext-mongodb >= 2.2`.
- **`.env` et Apache** : le fichier doit rester lisible par `www-data` (`640`, groupe `www-data`), sinon l'application demarre sans configuration (erreur `APP_KEY`/nom « Laravel »).
- **Microservice au demarrage** : Next.js met quelques secondes a ecouter apres un `restart` ; le smoke test integre une attente active. Le token du microservice (`.env.local`) doit correspondre a un jeton actif de `api_tokens`.
- **Migration `interventions`** : conserver l'horodatage `183115` (apres `tickets`), sinon echec de cle etrangere.
- **Boucle locale HTTPS** : `/etc/hosts` fait resoudre le domaine vers `127.0.0.1` (le microservice appelle l'API en HTTPS sans dependre du hairpin NAT).
- **Disque** : partition `/` proche de la saturation ; surveiller (sonde) et purger les caches de build si besoin.

## 8. Reprise rapide (checklist)

1. `ssh` sur la production, `cd /var/www/opstrack`.
2. `bash deploy/healthcheck.sh` — etat global.
3. Consulter les journaux pertinents (§ 5).
4. En cas d'incident applicatif : `storage/logs/laravel.log` + MongoDB `app_events`.
5. En cas de deploiement : `deploy/update-prod.sh` (rollback automatique).
6. En cas de perte de donnees : restaurer depuis `/var/backups/opstrack/` (§ 6).
