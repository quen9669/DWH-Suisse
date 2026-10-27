# 10. Bonnes pratiques

> 📝 **À compléter** : la page des bonnes pratiques utilisée en entreprise sera fournie plus tard. Ce document liste celles **déjà appliquées** dans le projet. La phase 8 de la [roadmap](../ROADMAP.md) consistera à comparer les deux et à aligner le projet.

## Bonnes pratiques déjà appliquées

### Architecture

| # | Pratique | Application |
|---|---|---|
| A1 | Séparer les couches dans des bases distinctes | `CH_ODS`, `CH_STG`, `CH_DWH`, `CH_ADMIN` |
| A2 | L'ODS conserve la donnée **brute** (texte, noms d'origine) | Aucune transformation avant STG |
| A3 | Colonnes d'audit sur chaque ligne chargée | `_BatchId`, `_SourceFile`, `_LoadDtm` |
| A4 | Le cube lit des **vues**, jamais des tables | Schéma `cube` |
| A5 | Une ligne « Inconnu » (-1) par dimension | Aucun fait perdu |
| A6 | Clés techniques dans le DWH, clés métier conservées | `StationKey` / `Uic` |

### SSIS

| # | Pratique | Application |
|---|---|---|
| S1 | Modèle de déploiement **par projet** | `DeploymentModel = Project` |
| S2 | **Connexions partagées** au niveau du projet | `CM_ADMIN`, `CM_ODS`, `CM_STG`, `CM_DWH` |
| S3 | Aucun chemin ni serveur codé en dur : **paramètres + expressions** | `Project.params` |
| S4 | Un **master package** orchestre, un package enfant par étape | `00_MASTER` + 8 enfants |
| S5 | Préfixes de nommage des packages et des tâches | Voir [05_Packages_SSIS.md](05_Packages_SSIS.md#convention-de-nommage) |
| S6 | **Description** renseignée sur chaque package et chaque tâche | Fenêtre Propriétés |
| S7 | Journalisation fonctionnelle (lot / étape / fichier) en plus de SSISDB | Base `CH_ADMIN` |
| S8 | Gestionnaire `OnError` sur chaque package | Marque l'étape ou le lot en échec |
| S9 | `ProtectionLevel = DontSaveSensitive` + authentification Windows | Aucun mot de passe dans les packages, compatible Git |
| S10 | Chargement rapide (*fast load*, `TABLOCK`) vers les grosses tables | Data Flows ODS |
| S11 | `DelayValidation = True` sur ce qui dépend de fichiers créés à l'exécution | Data Flows, connexions fichier plat |
| S12 | Archivage des fichiers traités | File System Task vers `archive\` |

### SQL

| # | Pratique | Application |
|---|---|---|
| Q1 | Scripts **ré-exécutables** | `IF OBJECT_ID ... IS NULL`, `CREATE OR ALTER`, `MERGE` |
| Q2 | Chargements **idempotents** | Suppression puis insertion par fichier ou par jour |
| Q3 | Transactions + `TRY/CATCH` + journalisation de l'erreur + `THROW` | Toutes les procédures DWH |
| Q4 | `TRY_CONVERT` en STG plutôt que `CONVERT` | Une ligne invalide va en rejet au lieu de tout planter |
| Q5 | Rejets conservés avec leur motif | `stg.Istdaten_Rejet` |
| Q6 | Détection des changements par empreinte | `HashDiff` (SHA-256) pour la SCD2 |
| Q7 | Commentaires d'en-tête sur chaque script (rôle, base, ré-exécutabilité) | Tous les fichiers `sql\` |

### Projet et Git

| # | Pratique | Application |
|---|---|---|
| G1 | Pas de données ni de fichiers générés dans Git | `.gitignore` (`bin`, `obj`, `*.user`, données) |
| G2 | Documentation à côté du code | Dossier `docs\` |
| G3 | Contrôles après chargement documentés | `sql\99_Controles.sql` |

## Écarts connus (à traiter)

| Écart | Pourquoi | Piste |
|---|---|---|
| Droits larges pour SQL Agent (`db_owner`) | Simplicité en développement | Rôles dédiés en lecture/écriture |
| Pas de tests automatisés | Hors périmètre initial | tSQLt (phase 9) |
| Transformations en T-SQL plutôt qu'en Data Flow | Choix ELT assumé (performance) | Exercice 5 pour pratiquer les deux |

## Bonnes pratiques de l'entreprise

*(section à remplir avec la page fournie)*
