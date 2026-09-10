# Journal de securite

Ce document recense les failles de securite identifiees pendant l'epreuve, leur evaluation et les mesures correctives appliquees. Details et preuves : `../04_supervision_maintien.md`.

## Faille 1 — Injection SQL (recherche de tickets)

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | `App\Http\Controllers\Api\TicketController@index` |
| Description de la faille | Le terme de recherche etait interpole directement dans `orWhereRaw("reference like '%{$search}%'")`, sans binding. |
| Severite estimee | `Critique` |
| Impact potentiel | Exfiltration/alteration de donnees via injection (`OR 1=1`, `UNION`, sous-requetes) sur un parametre controle par l'appelant. |
| Mesure corrective appliquee | Requete parametree (`orWhere` avec bindings) et groupement des clauses en closure. |
| Statut | `Corrige` |
| Preuve de correction | `GET /api/v1/tickets?search=' OR '1'='1' --` -> `200`, 0 resultat (aucune fuite) ; test automatise `TicketSearchTest`. |

## Faille 2 — Dependance vulnerable (microservice Next.js)

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | `microservices/dispatch-dashboard` — `next@15.3.1` |
| Description de la faille | Version de Next.js portant la vulnerabilite CVE-2025-66478 (signalee par `npm install`). |
| Severite estimee | `Haute` |
| Impact potentiel | Exploitation de la vulnerabilite connue du framework du microservice. |
| Mesure corrective appliquee | Recommandation : montee de version vers un correctif `15.3.x` via le pipeline (build + smoke test). Isolation du microservice (service dedie, ecoute `127.0.0.1`, expose via proxy). |
| Statut | `Identifie, non corrige` (montee de version a valider) |
| Preuve de correction | — (avertissement `npm` conserve dans les journaux de build) |

## Faille 3 — Authentification du webhook limitee

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | `public/hooks.php` / `WebhookController` |
| Description de la faille | Authentification par HTTP Basic uniquement, sans signature ni restriction d'origine. |
| Severite estimee | `Moyenne` |
| Impact potentiel | Rejeu ou usurpation d'evenements si le secret fuite ; pas de garantie d'integrite du message. |
| Mesure corrective appliquee | Secret fort genere (hors depot) ; deduplication `external_event_id` limitant le rejeu. Recommandation : signature HMAC + liste d'origines autorisees. |
| Statut | `Mitigation en place` |
| Preuve de correction | `POST /hooks.php` sans identifiants -> `401` ; rejeu d'un `external_event_id` -> `already processed`. |

## Faille 4 — Secrets de demonstration et mode debug

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | `.env` de production / `.env.example` |
| Description de la faille | Identifiants de demonstration et `APP_DEBUG=true` exposaient secrets et stacktraces. |
| Severite estimee | `Haute` |
| Impact potentiel | Fuite de secrets et d'informations techniques via les pages d'erreur. |
| Mesure corrective appliquee | `.env` de production avec secrets forts generes, `APP_DEBUG=false`, fichier en `640` (`ubuntu:www-data`), jamais versionne. |
| Statut | `Corrige` |
| Preuve de correction | `/api/health` renvoie le nom applicatif sans fuite ; pages d'erreur sans stacktrace. |

## Faille 5 — Portee des tokens d'API

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | `App\Http\Middleware\EnsureApiTokenIsValid` |
| Description de la faille | Le middleware valide l'existence/activation du token mais ne verifie pas les `abilities` par ressource. |
| Severite estimee | `Moyenne` |
| Impact potentiel | Un token compromis dispose d'un acces large, sans cloisonnement par action. |
| Mesure corrective appliquee | Recommandation : controle des `abilities` (deja stockees en base) au niveau du middleware/route. |
| Statut | `Identifie, non corrige` |
| Preuve de correction | — |

## Faille 6 — Mot de passe `root` MySQL faible

| Champ | Description |
| --- | --- |
| Date de detection | 10 septembre 2026 |
| Composant concerne | Serveur MySQL (production) |
| Description de la faille | Compte `root` avec mot de passe trivial (`0000`). |
| Severite estimee | `Basse` (non expose hors `localhost`) |
| Impact potentiel | Elevation en cas d'acces local non autorise. |
| Mesure corrective appliquee | MySQL en ecoute `127.0.0.1` uniquement ; application connectee via un utilisateur dedie a privileges limites. Recommandation : rotation du mot de passe `root`. |
| Statut | `Mitigation en place` |
| Preuve de correction | `ss -tlnp` : `mysqld` lie a `127.0.0.1:3306` uniquement. |
