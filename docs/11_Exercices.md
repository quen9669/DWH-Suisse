# 11. Exercices pour monter en compétence

Le projet fonctionne « clé en main ». Pour **apprendre**, refaites certaines parties vous-même. Les exercices sont classés par difficulté : ⭐ facile, ⭐⭐ moyen, ⭐⭐⭐ avancé.

> Conseil Git : faites chaque exercice dans une **branche** (`git checkout -b exercice-05`). Si vous cassez quelque chose, il suffit de revenir à `main`.

---

## Exercice 1 ⭐ : premier package de A à Z

**Objectif** : créer un package simple sans aide.

1. Créez un package `90_TEST_Comptage.dtsx`.
2. Ajoutez une *Execute SQL Task* qui lit `SELECT COUNT(*) FROM ods.Istdaten` (connexion `CM_ODS`), avec le résultat « ligne unique » dans une variable `User::NbLignes` (Int32).
3. Ajoutez une deuxième tâche qui écrit cette valeur dans une table de votre choix.
4. Exécutez, puis posez un *breakpoint* pour voir la valeur de la variable (fenêtre *Locals*).

🧠 Variables, ResultSet, connexions de projet, débogage.

## Exercice 2 ⭐ : paramètre et expression

Ajoutez un paramètre de projet `ModeTestUnJour` (Boolean). Quand il vaut `true`, `NbJoursIstdaten` doit être ignoré et 1 seul jour téléchargé. *Indice* : expression sur la propriété `Arguments` de la tâche de `10_EXT_Telechargement`, avec l'opérateur conditionnel `condition ? valeur1 : valeur2`.

## Exercice 3 ⭐⭐ : nouvelle règle de qualité

Dans `stg.usp_Load_Istdaten`, rejetez les lignes dont l'heure de départ prévue est **antérieure** à l'heure d'arrivée prévue (motif : *« Départ avant arrivée »*).
- Ajoutez la règle dans le `CASE ... AS RejectReason` **et** dans le filtre des lignes valides.
- Rechargez, puis vérifiez avec la requête 4 de `99_Controles.sql`.

🧠 Règles de qualité, cohérence entre rejets et lignes valides.

## Exercice 4 ⭐⭐ : simuler un changement SCD2

1. Après un chargement, modifiez à la main le nom d'une gare **dans la STG** :
   ```sql
   UPDATE CH_STG.stg.ServicePoint
      SET StationName = N'Zürich HB (test)',
          HashDiff = HASHBYTES('SHA2_256', N'test')
    WHERE Uic = 8503000;
   ```
2. Exécutez `EXEC CH_DWH.etl.usp_Load_DimStation @BatchId = 0;`.
3. Observez `SELECT * FROM CH_DWH.dim.Station WHERE Uic = 8503000;`. Que se passe-t-il si vous relancez le même jour ? Et le lendemain ?

🧠 SCD type 2, `ValidFrom`/`ValidTo`, cas du changement le jour même.

## Exercice 5 ⭐⭐⭐ : dimension en Data Flow pur (sans procédure)

Remplacez `etl.usp_Load_DimOperator` par un Data Flow :

```
OLE DB Source (SELECT DISTINCT OperatorId, OperatorAbbr, OperatorName FROM stg.Istdaten)
   → Lookup sur dim.Operator (par OperatorId)
        ├─ No Match  → OLE DB Destination (insertion)
        └─ Match     → Conditional Split (nom ou abréviation différents ?)
                          └─ Changé → OLE DB Command (UPDATE)  ou  table tampon + UPDATE ensembliste
```

Comparez ensuite les deux approches (lisibilité, performance, maintenance). C'est une question classique d'entretien.

🧠 Lookup (cache complet), Conditional Split, OLE DB Command et ses limites, pattern « table tampon ».

## Exercice 6 ⭐⭐ : l'assistant SCD de SSIS

Refaites la dimension `dim.Operator` avec le composant **Slowly Changing Dimension** de SSIS (assistant intégré). Observez le Data Flow généré. Pourquoi est-il réputé lent sur de gros volumes ?

## Exercice 7 ⭐⭐ : déploiement SSISDB et environnements

1. Déployez le projet dans SSISDB.
2. Créez deux environnements, `DEV` (3 jours) et `TEST` (1 jour), avec une variable `NbJours`.
3. Liez le paramètre `NbJoursIstdaten` à cette variable.
4. Exécutez le master avec chaque environnement.

🧠 Catalogue SSISDB, environnements, références, configuration sans modifier le code.

## Exercice 8 ⭐⭐⭐ : partitions mensuelles du cube

1. Dans le modèle, remplacez la partition unique de `Passages` par une partition par mois (`WHERE DateKey BETWEEN 20261001 AND 20261031`).
2. Modifiez `Invoke-ProcessCube.ps1` pour ne traiter que la partition du mois courant + les dimensions.
3. Comparez la durée de traitement.

🧠 Partitions, traitement incrémental, TMSL.

## Exercice 9 ⭐⭐⭐ : nouvelle source GTFS (horaires théoriques)

Ajoutez la source GTFS suisse (fichier ZIP contenant `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`, `calendar.txt`...).
- Nouveau package `23_ODS_GTFS` avec une boucle sur les fichiers du ZIP.
- Nouveau fait `fact.ScheduledStop` : offre planifiée.
- Mesure DAX : *taux de réalisation* (passages réels ÷ passages planifiés).

🧠 Source multi-fichiers liés, gros volumes (`stop_times` = plusieurs dizaines de millions de lignes), modélisation d'un second processus métier.

## Exercice 10 ⭐ : tableau de bord d'exploitation

Créez une page Power BI branchée **directement** sur `CH_ADMIN` (mode Import) : durée des lots, lignes par étape, taux de rejet. C'est le genre de rapport que demandent les équipes d'exploitation.
