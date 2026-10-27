# 9. Glossaire

Les termes sont classés par ordre alphabétique, avec une explication simple puis, si utile, l'exemple du projet.

| Terme | Explication simple | Dans ce projet |
|---|---|---|
| **Agrégation** | Résumer beaucoup de lignes en un chiffre (somme, moyenne, comptage) | Le taux de ponctualité agrège des millions de passages |
| **BOM** | Quelques octets invisibles en début de fichier, qui indiquent son encodage | Le fichier des arrêts commence par un BOM UTF-8 |
| **Catalogue SSISDB** | La « bibliothèque » de SQL Server où l'on dépose les projets SSIS pour les exécuter en production | Phase 5 |
| **Clé métier** | L'identifiant utilisé par la source | `Uic` = 8503000 pour Zurich HB |
| **Clé technique (de substitution)** | Un numéro interne à l'entrepôt, indépendant de la source | `StationKey` ; plusieurs par gare avec la SCD2 |
| **Columnstore** | Stockage d'une table colonne par colonne : très compressé et rapide pour les totaux | `fact.StopEvent`, `ods.Istdaten` |
| **Connexion active (*live*)** | Power BI interroge le cube en direct, sans copier les données | Page 7 |
| **Control Flow** | Dans SSIS, l'enchaînement des **tâches** (exécuter du SQL, boucler, lancer un autre package) | Onglet *Control Flow* |
| **Cube / modèle sémantique** | Couche d'analyse prête à l'emploi : noms métier, formules, sécurité | `DWH_Suisse_Cube` |
| **Data Flow** | Dans SSIS, un **tuyau** où circulent les lignes : source → transformations → destination | `DFT Charger ods Istdaten` |
| **DAX** | Le langage de formules de SSAS Tabular et de Power BI | `DIVIDE ( [Nb passages ponctuels], [Nb passages mesurés] )` |
| **Dimension** | Un axe d'analyse : quand, où, qui, quoi | Date, Gare, Opérateur |
| **Dimension dégénérée** | Un identifiant gardé dans la table de faits, sans table de dimension | `TripId` |
| **DWH (Data Warehouse)** | L'entrepôt de données : données propres, historisées, organisées pour l'analyse | Base `CH_DWH` |
| **ELT / ETL** | *Extract, Transform, Load* : extraire, transformer, charger. En ELT, la transformation est faite par la base elle-même. | SSIS orchestre, SQL transforme |
| **Expression (SSIS)** | Une petite formule qui calcule une valeur dynamiquement | Chemin du fichier = `@[$Project::DataFolder] + "\\istdaten"` |
| **Fait / table de faits** | Les événements mesurés, avec des nombres | `fact.StopEvent` = les passages |
| **Grain** | Ce que représente exactement **une** ligne d'une table de faits | Un trajet à un arrêt un jour donné |
| **Idempotent** | Qu'on peut relancer plusieurs fois avec le même résultat (pas de doublons) | Tous les chargements du projet |
| **JSON** | Format texte structuré, très utilisé par les API web | Réponses météo |
| **Lot (*batch*)** | Une exécution complète du chargement, avec un numéro unique | `BatchId` dans `CH_ADMIN.etl.Batch` |
| **Master package** | Le package « chef d'orchestre » qui appelle les autres dans le bon ordre | `00_MASTER.dtsx` |
| **Membre déduit (*inferred member*)** | Une ligne de dimension créée en urgence, car un fait la cite avant qu'elle n'existe | Arrêts étrangers |
| **Membre inconnu** | La ligne « -1 » de chaque dimension, pour ne jamais perdre un fait | « Opérateur inconnu » |
| **Mesure** | Une formule de calcul définie dans le cube | Taux de ponctualité |
| **ODS (Operational Data Store)** | La zone de dépôt des données **brutes**, telles que reçues | Base `CH_ODS` |
| **OLE DB** | Une technologie de connexion aux bases de données utilisée par SSIS et SSAS | Pilote `MSOLEDBSQL` |
| **Package** | Un fichier SSIS (`.dtsx`) qui contient un traitement | 9 packages |
| **Paramètre (de projet / de package)** | Une valeur réglable de l'extérieur, sans modifier le package | `NbJoursIstdaten`, `BatchId` |
| **Partition** | Un morceau d'une table (par mois, par exemple), traitable séparément | Exercice 8 |
| **Procédure stockée** | Un programme SQL enregistré dans la base | `stg.usp_Load_Istdaten` |
| **Rejet** | Une ligne écartée car invalide, conservée avec son motif | `stg.Istdaten_Rejet` |
| **RLS (sécurité au niveau des lignes)** | Chaque utilisateur ne voit que « ses » lignes | Rôle *Lecteurs Suisse romande* |
| **SCD (Slowly Changing Dimension)** | La façon de gérer les changements d'une dimension. **Type 1** : on écrase. **Type 2** : on garde l'historique (nouvelle version). | Opérateur : type 1 ; Gare : type 2 |
| **Schéma en étoile** | Une table de faits au centre, entourée de dimensions | Voir doc 4 |
| **SQL Server Agent** | Le planificateur de tâches de SQL Server | Job quotidien à 06:00 |
| **SSAS** | *SQL Server Analysis Services* : le moteur de cubes | Modèle tabulaire |
| **SSIS** | *SQL Server Integration Services* : l'outil d'alimentation de données (ETL) | Projet `DWH_Suisse_ETL` |
| **SSMS** | *SQL Server Management Studio* : l'outil pour explorer et interroger SQL Server | |
| **STG (Staging)** | La zone de préparation : on type, on contrôle, on calcule | Base `CH_STG` |
| **Tabular** | Le mode moderne de SSAS (en mémoire, langage DAX), le même moteur que Power BI | |
| **TMSL** | Langage JSON pour piloter un modèle tabulaire (déployer, traiter) | `Invoke-ProcessCube.ps1` |
| **UIC / BPUIC** | Numéro international officiel d'un arrêt ferroviaire ou de transport public | 8503000 |
