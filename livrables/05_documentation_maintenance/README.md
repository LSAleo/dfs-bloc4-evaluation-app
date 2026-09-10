# Documentation technique et transfert de connaissances

> Competence evaluee : `C27` — Produire la documentation technique d'une application et alimenter une base de connaissances pour la maintenance.

Ensemble documentaire produit pour la reprise de maintenance d'**OpsTrack Field Service** (candidat 07 — MARQUE Leo, session du 10 septembre 2026).

## Contenu

| Fichier | Description |
| --- | --- |
| [`documentation_technique/`](documentation_technique/README.md) | Documentation technique generee a partir du code source (hors dependances tierces) |
| [`documentation_api.md`](documentation_api.md) | Documentation de l'API REST `/api/v1` et du webhook |
| [`CHANGELOG.md`](CHANGELOG.md) | Journal des modifications apportees pendant l'epreuve |
| [`SECURITY.md`](SECURITY.md) | Journal des failles de securite et corrections |
| [`base_connaissances.md`](base_connaissances.md) | Note de passation (fonctionnement, exploitation, reprise) |

## Livrables associes

- `../01_architecture_hebergement.md` — architecture cible et hebergement (C29)
- `../02_exploitation_securisee.md` — production, DNS/HTTPS, durcissement (C28, C30)
- `../03_deploiement_ci_cd.md` — pipeline de deploiement (C31)
- `../04_supervision_maintien.md` — supervision, sauvegarde, correctifs (C32)

## Remarque sur le format de rendu

Le template prevoit une remise en archive `05_documentation_maintenance.zip`. Ici, l'ensemble est fourni versionne dans le depot (dossier `livrables/05_documentation_maintenance/`) et rendu par Pull Request, conformement a la modalite GitHub retenue.
