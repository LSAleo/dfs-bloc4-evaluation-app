# Supervision, journalisation, sauvegarde et maintenance corrective

> Competence evaluee : `C32` — Mettre en oeuvre un systeme de supervision pour detecter, diagnostiquer et corriger bugs, incidents et failles.

> Mise en oeuvre sur la production `eval-dfs-p-tpl-20265-07.it-students.fr`. Scripts versionnes : [`deploy/healthcheck.sh`](../deploy/healthcheck.sh), [`deploy/backup.sh`](../deploy/backup.sh), [`deploy/setup-supervision.sh`](../deploy/setup-supervision.sh).

---

## 1. Journalisation

### 1.1 Services journalises

| Service | Emplacement des journaux | Niveau de detail |
| --- | --- | --- |
| Application Laravel | `storage/logs/laravel.log` | `LOG_LEVEL` (erreurs, exceptions avec stacktrace) |
| Evenements applicatifs | MongoDB, collection `opstrack_logs.app_events` | evenements metier (`EventLogService`) : API, webhook, integrations |
| Serveur web Apache | `/var/log/apache2/opstrack_access.log` et `opstrack_error.log` | acces (combined) + erreurs PHP |
| Microservice Next.js | `journalctl -u opstrack-dispatch-dashboard` | sortie du service (systemd) |
| Pare-feu applicatif | `fail2ban` (journal systemd) | tentatives d'intrusion detectees/bannies |
| Sonde de sante | syslog, tag `opstrack-health` + `/var/log/opstrack-health.log` | anomalies (priorite `user.err`) |

### 1.2 Configuration de la journalisation

- **Rotation** : `logrotate` (`/etc/logrotate.d/opstrack`) applique une rotation quotidienne des journaux Laravel, 14 jours de retention, compression et `copytruncate` (evite la saturation disque, point de vigilance releve a 87 % d'occupation).
- **Centralisation legere** : les anomalies de supervision sont envoyees a `syslog` via `logger`, exploitables par `journalctl` ou un collecteur externe.
- **Tracabilite metier** : `EventLogService` journalise chaque appel API, webhook et integration dans MongoDB, avec un try/catch qui degrade proprement si MongoDB est indisponible (pas d'interruption de service).

---

## 2. Outils et configurations d'audit

- **fail2ban** installe et actif, jails : `sshd`, `apache-auth`, `apache-badbots` (`bantime 1h`, `maxretry 5`). Motivation : les journaux Apache montraient des **scans hostiles reels** (voir § 6.2 et § 7) — path traversal et sondes automatisees.
- **UFW** (cf. livrable 02) : reduction de la surface exposee a `22/80/443`.
- **CloudTrail / GuardDuty** cibles en architecture managee (cf. livrable 01) pour l'audit d'infrastructure.

Verification :

```
$ sudo fail2ban-client status
Jail list: apache-auth, apache-badbots, sshd
```

---

## 3. Supervision et alertes

### 3.1 Sondes mises en place

`deploy/healthcheck.sh`, execute toutes les 5 minutes par cron :

| Sonde | Cible | Seuil ou condition | Action en cas d'alerte |
| --- | --- | --- | --- |
| Etat des services | `apache2`, `mysql`, `mongod`, `redis-server`, `opstrack-dispatch-dashboard` | `systemctl is-active` != active | log `user.err` + code de sortie non nul |
| Disponibilite applicative | `https://…/api/health` | code HTTP != 200 | log `user.err` |
| Espace disque | partition `/` | occupation >= 90 % | log `user.err` |
| Expiration TLS | certificat du domaine | < 15 jours avant expiration | log `user.err` |

### 3.2 Mecanisme d'alerte

Chaque anomalie est ecrite dans `syslog` (tag `opstrack-health`, priorite `user.err`) et dans `/var/log/opstrack-health.log`. Ce canal est directement exploitable pour un relais e-mail (`mail`), une notification (webhook) ou un collecteur (Prometheus node-exporter / CloudWatch agent en cible). La sonde renvoie un code de sortie non nul, ce qui permet aussi son integration a un ordonnanceur externe.

Preuve d'execution :

```
OK: service apache2 actif
OK: service mysql actif
OK: service mongod actif
OK: service redis-server actif
OK: service opstrack-dispatch-dashboard actif
OK: https api/health = 200
OK: disque / a 87%
OK: certificat TLS valide 89 j
```

---

## 4. Strategie de sauvegarde et restauration

### 4.1 Elements sauvegardes

`deploy/backup.sh`, planifie quotidiennement (03h00) par cron :

| Element | Methode | Frequence | Retention |
| --- | --- | --- | --- |
| Base relationnelle MySQL `opstrack` | `mysqldump --single-transaction --quick --no-tablespaces` puis gzip | quotidienne | 7 jours |
| Base NoSQL MongoDB `opstrack_logs` | `mongodump --gzip --archive` | quotidienne | 7 jours |
| Secrets / configuration (`.env`) | copie `chmod 600` | quotidienne | 7 jours |

Les sauvegardes sont stockees sous `/var/backups/opstrack/<horodatage>/`. En cible (livrable 01), externalisation vers **S3** (versioning + chiffrement KMS) et **PITR** RDS.

### 4.2 Procedure de restauration

1. Selectionner la sauvegarde : `/var/backups/opstrack/<horodatage>/`.
2. Restaurer MySQL : `gunzip < mysql-opstrack.sql.gz | mysql -u… opstrack`.
3. Restaurer MongoDB : `mongorestore --gzip --archive=mongo-opstrack_logs.archive.gz`.
4. Restaurer la configuration si necessaire (`.env`), puis `php artisan config:clear`.

**Preuve de validation** (restauration reelle du dump dans une base temporaire, puis suppression) :

```
Dernière sauvegarde : /var/backups/opstrack/20260910-121152/
tickets restaurés : 2
users restaurés : 3
interventions restaurées : 5
base temporaire supprimée (test terminé)
```

La restauration a ete validee sans interruption de la base de production (base temporaire dediee).

---

## 5. Diagnostic et correction du bug technique

### 5.1 Symptome observe

« Le webhook `hooks.php` est bien appele regulierement, mais certaines mises a jour externes ne se repercutent pas. » En pratique, **tout appel** a `hooks.php` echouait.

### 5.2 Demarche de diagnostic

- Test direct : `curl -X POST https://…/hooks.php` -> **HTTP 500**.
- Lecture du journal Apache `opstrack_error.log` :

```
PHP Fatal error: Uncaught ... BindingResolutionException:
Target class [config] does not exist. in .../Container.php
#7 .../app/Http/Controllers/WebhookController.php(19): config()
#8 .../public/hooks.php(12): WebhookController->handle()
```

### 5.3 Cause racine identifiee

`public/hooks.php` instanciait le `WebhookController` et appelait `handle()` **sans amorcer le framework** : le point d'entree court-circuitait le kernel HTTP, si bien que le conteneur n'avait ni la configuration (`config()`) ni le binding `request`. Le webhook ne pouvait donc jamais s'executer.

### 5.4 Correctif applique

Dans [`public/hooks.php`](../public/hooks.php) : amorçage explicite du framework et liaison de la requete au conteneur avant de resoudre le controleur.

```php
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();                 // charge env, configuration, providers
$request = Request::capture();
$app->instance('request', $request);  // requete disponible dans le conteneur
$response = $app->make(WebhookController::class)->handle($request);
```

Deux defauts fonctionnels du `WebhookController` ont ete corriges dans la foulee (cf. § 7) : **absence de deduplication** sur `external_event_id` et **forcage du ticket sur `scheduled`**.

### 5.5 Verification apres correction

```
# sans authentification -> 401 (et non plus 500)
POST /hooks.php                              -> 401

# avec authentification + payload
POST /hooks.php {ticket_reference, status, external_event_id}
  -> {"message":"Webhook processed.","intervention_id":4}

# rejeu du meme external_event_id -> deduplication
  -> {"message":"Webhook already processed.","intervention_id":4}
# (COUNT interventions pour cet event_id = 1)

# le ticket reflete le statut du webhook (payload status=resolved)
statut INC-240302 en base = resolved
```

---

## 6. Diagnostic et correction de la faille de securite

### 6.1 Faille identifiee

**Injection SQL** dans `TicketController@index` : le terme de recherche etait interpole directement dans une clause SQL brute.

```php
$query->where('title', 'like', "%{$search}%")
      ->orWhereRaw("reference like '%{$search}%'");   // <-- interpolation directe
```

### 6.2 Demarche de diagnostic

- Revue de code (recherche des `*Raw` et concatenations SQL).
- Constat que `$request->string('search')` est injecte sans binding dans `orWhereRaw`.
- Correlation avec les journaux : trafic de scan automatise deja present (IP `45.156.128.0/22`, sondes de type path traversal), confirmant l'exposition a des tentatives d'exploitation.

### 6.3 Evaluation du risque

- **Criticite : elevee.** Un parametre `search` non authentifie cote SQL permet l'exfiltration ou l'alteration de donnees (`UNION`, sous-requetes, `OR 1=1`).
- **Surface** : endpoint API accessible avec un token ; la faille aggrave tout compromis de token.
- Defaut connexe : **groupement de clauses incorrect** (`where()->orWhere...` sans parentheses) faussait aussi les resultats combines avec le filtre `priority`.

### 6.4 Mesure corrective appliquee

Requete **parametree** (bindings) et **groupement en closure** dans [`TicketController.php`](../app/Http/Controllers/Api/TicketController.php) :

```php
$query->where(function ($q) use ($search): void {
    $q->where('title', 'like', "%{$search}%")
      ->orWhere('reference', 'like', "%{$search}%");
});
```

Defense en profondeur complementaire : **AWS WAF** en cible (livrable 01) et durcissement de l'API (cf. § 7).

### 6.5 Verification apres correction

```
# charge d'injection -> pas d'erreur SQL, requete parametree
GET /api/v1/tickets?search=' OR '1'='1 --   -> 200 (aucune fuite)

# recherche + filtre priorite -> resultat coherent (groupement correct)
GET /api/v1/tickets?search=INC-2403&priority=critical
  -> ["INC-240301"]   (INC-240302 'medium' correctement exclu)
```

---

## 7. Autres observations

**Autres correctifs apportes (bugs fonctionnels) :**

| Composant | Defaut | Correctif |
| --- | --- | --- |
| `DashboardController` | KPI en cache 30 min sans invalidation -> compteurs obsoletes | `TicketObserver` qui purge `dashboard.kpis` a chaque mutation de ticket |
| `WebhookController` | pas de deduplication `external_event_id` | idempotence : rejeu -> intervention existante renvoyee |
| `WebhookController` | ticket force sur `scheduled` | le ticket reflete le statut transmis |
| Microservice Next.js | lecture `payload.items` au lieu de `payload.data` -> dashboard vide | correction de la cle -> les tickets s'affichent |

**Source des appels suspects (traçabilite).** Les journaux Apache identifient des sondes automatisees hostiles : `45.156.128.168-171` (path traversal, `AH10244: invalid URI path`), balayages `/wp-json`, `/phpmyadmin`, `xmldata`. Ces points d'entree exposes justifient fail2ban et le durcissement du livrable 02. Le webhook `hooks.php` recevait aussi des appels externes reels (`curl`) — desormais authentifies et fonctionnels.

**Failles residuelles / recommandations :**

| Point | Risque | Recommandation |
| --- | --- | --- |
| `next@15.3.1` (CVE-2025-66478) | vulnerabilite connue du microservice | mise a jour vers un correctif 15.3.x via le pipeline (test + smoke) |
| API par token sans permissions fines | portee large d'un token compromis | verifier les `abilities` par ressource au niveau du middleware |
| `hooks.php` : HTTP Basic uniquement | rejeu / usurpation si secret fuite | ajouter une signature HMAC et une restriction d'origine |
| `root` MySQL en `0000` | acces admin faible (non expose hors localhost) | rotation du mot de passe `root` |

Ces points sont consignes dans `05_documentation_maintenance/SECURITY.md`.
