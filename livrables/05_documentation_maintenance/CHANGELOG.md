# Changelog

Toutes les modifications notables apportees pendant l'epreuve sont documentees dans ce fichier.
Le format s'inspire de [Keep a Changelog](https://keepachangelog.com/).

## [Session du 10 septembre 2026] — Candidat 07 (MARQUE Leo)

### Ajoute

- **Mise en service de la production** `eval-dfs-p-tpl-20265-07.it-students.fr` (Apache, PHP 8.4, MySQL, MongoDB, Redis, microservice Next.js) — cf. `02_exploitation_securisee.md`.
- **HTTPS** via Let's Encrypt (`certbot --apache`) avec redirection HTTP -> HTTPS et renouvellement automatique.
- **Pare-feu UFW** (22/80/443) et **fail2ban** (jails `sshd`, `apache-auth`, `apache-badbots`).
- **Pipeline CI/CD** GitHub Actions en deux paliers (qualification -> production) : `.github/workflows/deploy.yml`.
- **Scripts d'exploitation** : `deploy/provision-prod.sh` (provisioning), `deploy/update-prod.sh` (deploiement + rollback), `deploy/backup.sh` (sauvegarde), `deploy/healthcheck.sh` (sonde), `deploy/setup-supervision.sh` (fail2ban/logrotate/cron).
- **`App\Observers\TicketObserver`** : invalidation du cache des KPI du tableau de bord.
- **Tests de non-regression** `tests/Feature/TicketSearchTest.php` (recherche/priorite, injection SQL).

### Modifie

- `public/hooks.php` : amorçage du framework (`kernel->bootstrap()`) et liaison de la requete au conteneur.
- `App\Http\Controllers\WebhookController` : deduplication par `external_event_id` et report du statut reel du webhook sur le ticket.
- `App\Providers\AppServiceProvider` : enregistrement de `TicketObserver`.
- `microservices/dispatch-dashboard/lib/api.ts` : lecture de la cle `data` de la reponse API.
- Migration `create_interventions_table` renommee (`183114` -> `183115`) pour s'executer apres `create_tickets_table` (dependance de cle etrangere).
- `.env` de production : `APP_ENV=production`, `APP_DEBUG=false`, secrets forts generes, droits `640`.

### Corrige

- **Webhook `hooks.php` inoperant (HTTP 500)** : « Target class [config] does not exist » — le point d'entree n'amorçait pas le framework. Les mises a jour externes ne se repercutaient jamais.
- **Recherche de tickets incoherente** avec le filtre de priorite : groupement de clauses `OR` corrige (closure).
- **Tableau de bord (KPI) obsoletes** : cache invalide a chaque mutation de ticket.
- **Tableau de bord Next.js vide** : mauvaise cle de reponse (`items` -> `data`).
- **Doublons d'interventions** sur rejeu de webhook : deduplication `external_event_id`.
- **Ecart de statut webhook/ticket** : le ticket n'est plus force sur `scheduled`.

### Securite

- **Injection SQL** dans `TicketController@index` (`orWhereRaw` interpole) corrigee par une requete parametree — cf. `SECURITY.md`.
- Durcissement production : `APP_DEBUG=false`, secrets hors depot (`.env` en `640`, jamais versionne), utilisateur MySQL applicatif a privileges limites, bases de donnees en ecoute `localhost` uniquement, `Options -Indexes`.
- Detection/blocage des scans hostiles via fail2ban (path traversal et sondes observes dans les journaux Apache).
- Failles residuelles documentees (CVE `next@15.3.1`, permissions de token, authentification du webhook) — cf. `SECURITY.md`.
