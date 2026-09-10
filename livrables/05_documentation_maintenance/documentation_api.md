# Documentation d'API

## 1. Vue d'ensemble de l'API

L'application OpsTrack expose une API REST versionnee consommee par les clients internes et le microservice `dispatch-dashboard`.

| Champ | Valeur |
| --- | --- |
| URL de base | `https://eval-dfs-p-tpl-20265-07.it-students.fr/api` |
| Version | `v1` (prefixe `/api/v1`) |
| Format | `JSON` |
| Authentification | Jeton API en en-tete `Authorization: Bearer <token>` (ou `X-Api-Token: <token>`) |
| Webhook entrant | `POST /hooks.php` — authentification HTTP Basic |

Les jetons sont stockes dans la table `api_tokens` (champ `is_active`) ; le microservice utilise la variable `LARAVEL_API_TOKEN`.

## 2. Endpoints disponibles

| Methode | Endpoint | Description | Authentification requise |
| --- | --- | --- | --- |
| `GET` | `/api/health` | Etat du service (sonde) | Non |
| `GET` | `/api/v1/tickets` | Liste paginee des tickets (filtres `search`, `priority`, `per_page`) | Oui (token) |
| `POST` | `/api/v1/tickets` | Creation d'un ticket | Oui (token) |
| `GET` | `/api/v1/tickets/{ticket}` | Detail d'un ticket | Oui (token) |
| `PUT/PATCH` | `/api/v1/tickets/{ticket}` | Mise a jour d'un ticket | Oui (token) |
| `GET` | `/api/v1/technicians` | Liste des techniciens | Oui (token) |
| `GET` | `/api/v1/external/weather?site_id={id}` | Enrichissement meteo d'un site (Open-Meteo) | Oui (token) |
| `POST` | `/hooks.php` | Webhook : synchronisation d'un evenement externe | Oui (HTTP Basic) |

## 3. Exemples de requetes et reponses

### Liste des tickets (avec recherche et filtre)

```http
GET /api/v1/tickets?search=INC-2403&priority=critical HTTP/1.1
Authorization: Bearer <token>
Accept: application/json
```

```json
{
  "data": [
    {
      "id": 1,
      "reference": "INC-240301",
      "title": "Intermittent payment terminal outage",
      "priority": "critical",
      "status": "in_progress",
      "site": { "id": 1, "name": "Lyon Confluence", "city": "Lyon" },
      "interventions": [ { "id": 1, "status": "in_progress" } ]
    }
  ],
  "links": { "first": "...", "last": "...", "next": null },
  "meta": { "current_page": 1, "per_page": 15, "total": 1 }
}
```

### Sante du service

```http
GET /api/health HTTP/1.1
```

```json
{ "status": "ok", "service": "OpsTrack", "timestamp": "2026-09-10T08:37:38+00:00" }
```

### Webhook entrant

```http
POST /hooks.php HTTP/1.1
Authorization: Basic <base64(user:password)>
Content-Type: application/json

{ "ticket_reference": "INC-240301", "status": "in_progress", "external_event_id": "evt-001" }
```

```json
{ "message": "Webhook processed.", "intervention_id": 4 }
```

Rejeu du meme `external_event_id` (idempotence) :

```json
{ "message": "Webhook already processed.", "intervention_id": 4 }
```

## 4. Codes d'erreur

| Code | Signification |
| --- | --- |
| `200` | Succes |
| `401` | Jeton API absent/invalide, ou identifiants webhook incorrects |
| `404` | Ressource introuvable (ex. `ticket_reference` inconnu) |
| `422` | Donnees invalides (validation du corps de requete) |
| `500` | Erreur serveur |

## 5. Notes

- La liste des tickets est **paginee** (`per_page`, defaut 15) ; les collections sont encapsulees sous la cle `data` (Laravel API Resource).
- Le filtre `search` porte sur le **titre** et la **reference** ; il est combinable avec `priority` (correctif du livrable 04).
- L'endpoint meteo depend de l'API publique Open-Meteo (integration externe tolerante a l'indisponibilite).
