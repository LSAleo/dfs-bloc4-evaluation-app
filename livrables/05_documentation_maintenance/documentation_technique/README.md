# Documentation technique — OpsTrack Field Service

Documentation generee a partir du **code source applicatif** (repertoires `app/`, `routes/`, `database/`, `public/`, `microservices/`), hors dependances tierces (`vendor/`, `node_modules/`).

Ce dossier contient deux documents complementaires :

| Document | Nature | Production |
| --- | --- | --- |
| Le present `README.md` | Vue d'ensemble commentee : architecture, responsabilites, flux | redige a la main |
| [`reference_classes.md`](reference_classes.md) | **Reference exhaustive** des classes et methodes publiques | **genere** par [`tools/generate-code-reference.php`](../../../tools/generate-code-reference.php) |

**Regeneration** (aucun prerequis, ni `vendor/` ni demarrage de l'application) :

```bash
php tools/generate-code-reference.php
```

Le generateur analyse `app/`, `database/seeders/` et `database/factories/` avec le tokenizer de PHP (`token_get_all`), et **exclut les dependances tierces** (`vendor/`, `node_modules/`) conformement a l'attendu. Il extrait namespaces, classes/interfaces/traits/enums, methodes publiques avec signature, et docblocks. Sortie deterministe : deux executions successives produisent un fichier identique, ce qui le rend rejouable dans le pipeline CI.

> **Le perimetre depend de l'arbre dans lequel le generateur est execute.** Chaque livrable etant rendu sur sa propre branche, la reference versionnee ici couvre le code present sur **cette** branche : **22 fichiers, 22 classes, 31 methodes publiques** (total recoupe avec un comptage independant du code source). Sur la branche integree, qui reunit les cinq livrables, une regeneration donne **23 classes et 34 methodes publiques** : la difference est la classe `App\Observers\TicketObserver` introduite par le livrable 04, mentionnee dans la vue d'ensemble ci-dessous. Il faut donc **rejouer `php tools/generate-code-reference.php` apres chaque integration**, ce qui est le comportement attendu d'un artefact genere.

## 1. Vue d'ensemble

OpsTrack est une application Laravel 12 (PHP 8.4) de gestion d'interventions terrain :
- un **front web** (tableau de bord) et une **API REST** `/api/v1` servis par Laravel ;
- un **webhook** entrant `public/hooks.php` ;
- un **microservice** Next.js (`dispatch-dashboard`) consommant l'API ;
- des donnees dans **MySQL** (metier), **MongoDB** (journaux), **Redis** (cache/sessions cible).

## 2. Arborescence du code

```
app/
  Http/Controllers/            controleurs web et API
    Api/TicketController.php    CRUD tickets + recherche
    Api/TechnicianController.php
    Api/ExternalContextController.php   meteo (Open-Meteo)
    DashboardController.php     tableau de bord web + KPI
    WebhookController.php       traitement du webhook
  Http/Middleware/EnsureApiTokenIsValid.php   auth par jeton API
  Http/Requests/               validation (StoreTicket, UpdateTicket)
  Http/Resources/TicketResource.php   serialisation JSON
  Models/                      Ticket, Intervention, Site, Customer, User, ApiToken
  Models/Mongo/EventLog.php    document MongoDB (app_events)
  Observers/TicketObserver.php invalidation cache KPI
  Providers/AppServiceProvider.php   enregistrement de l'observer
  Services/EventLogService.php journalisation MongoDB
  Services/PublicWeatherService.php   client Open-Meteo
routes/  web.php, api.php, console.php
database/migrations, database/seeders/DatabaseSeeder.php
public/index.php (front controller), public/hooks.php (webhook)
microservices/dispatch-dashboard/ (Next.js)
```

## 3. Controleurs

| Classe | Responsabilite | Points notables |
| --- | --- | --- |
| `Api\TicketController` | Lister / creer / afficher / mettre a jour les tickets | Recherche `title`/`reference` **parametree** et groupee (closure) ; ferme le ticket (`closed_at`) au passage `resolved`/`closed` ; journalise via `EventLogService`. |
| `DashboardController` | Rendu du tableau de bord web | KPI mis en cache `dashboard.kpis`, **invalides** par `TicketObserver`. |
| `WebhookController` | Traiter un evenement externe | Auth HTTP Basic ; **deduplication** `external_event_id` ; report du statut du webhook sur le ticket. |
| `Api\ExternalContextController` | Enrichissement meteo d'un site | Delegue a `PublicWeatherService` ; reponse encapsulee sous `data`. |
| `Api\TechnicianController` | Lister les techniciens | Lecture simple. |

## 4. Services

- **`EventLogService::record($channel, $eventType, $payload, $severity)`** : insere un document dans MongoDB (`app_events`). Encapsule dans un `try/catch` : si MongoDB est indisponible, l'evenement est journalise en warning et **le service continue** (pas d'interruption).
- **`PublicWeatherService::currentForSite(Site $site)`** : appelle l'API publique Open-Meteo (`config('services.public_weather.base_url')`), timeout 8 s, retourne la meteo courante.

## 5. Modeles et donnees

| Modele | Table / connexion | Relations |
| --- | --- | --- |
| `Ticket` | `tickets` (MySQL) | `site`, `openedBy`/`assignedTo` (User), `interventions` |
| `Intervention` | `interventions` (MySQL) | `ticket` ; `external_event_id` (idempotence webhook) |
| `Site` | `sites` (MySQL) | `customer` |
| `Customer`, `User`, `ApiToken` | MySQL | — |
| `Mongo\EventLog` | `app_events` (MongoDB) | journaux techniques (`payload` JSON) |

Schema : voir `database/migrations/`. **Ordre des migrations** : `create_interventions_table` porte l'horodatage `183115` pour s'executer apres `create_tickets_table` (dependance de cle etrangere `ticket_id`).

## 6. Securite applicative

- **`EnsureApiTokenIsValid`** (alias `api.token`) : lit le jeton (`Bearer` ou `X-Api-Token`), verifie son existence et `is_active`, met a jour `last_used_at`. Applique au groupe `/api/v1`.
- Webhook : authentification HTTP Basic (`services.webhook.*`), amorçage du framework dans `public/hooks.php`.
- Requetes parametrees (Eloquent/Query Builder) ; validation via `FormRequest`.

## 7. Routage

- `routes/web.php` : `/` -> `DashboardController`.
- `routes/api.php` : `/api/health` (public) ; groupe `/api/v1` sous `api.token` : `tickets` (apiResource), `technicians`, `external/weather`.
- `public/hooks.php` : point d'entree dedie du webhook (hors routeur), amorce le kernel puis appelle `WebhookController::handle()`.

## 8. Microservice `dispatch-dashboard`

Application Next.js 15 (App Router). `lib/api.ts` interroge `LARAVEL_API_BASE_URL/tickets` avec `LARAVEL_API_TOKEN` (Bearer) et lit la cle **`data`** de la reponse. `app/page.tsx` (Server Component) affiche les tickets. Servi par `systemd` (`opstrack-dispatch-dashboard`) sur `127.0.0.1:3000`, proxifie par Apache sous `/dispatch-dashboard`.

## 9. Configuration

Variables cles (`.env`) : `DB_*` (MySQL), `MONGODB_*`, `REDIS_*`, `OPSTRACK_API_TOKEN`, `WEBHOOK_BASIC_USER`/`WEBHOOK_BASIC_PASSWORD`, `PUBLIC_WEATHER_API_BASE`. Detail d'exploitation : `../../02_exploitation_securisee.md`.
