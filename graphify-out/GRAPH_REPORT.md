# Graph Report - dwh-suisse  (2026-11-06)

## Corpus Check
- 37 files · ~29,362 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 21 file(s) not represented in the graph (top: .dtsx 9, .conmgr 4, (none) 2)
- WARNING: 21 of 58 files seen (36%) have no supported extractor and are missing from this graph entirely. It may look complete while representing only part of the codebase.

## Summary
- 229 nodes · 357 edges · 20 communities (15 shown, 5 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 21 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7e0bcc82`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- generate_ssis.py
- child_package
- 5. Le projet SSIS `DWH_Suisse_ETL`
- README.md
- Erreurs courantes et solutions
- 1. Installation pas à pas
- 11. Exercices pour monter en compétence
- Roadmap : de l'installation au rapport Power BI
- Common.ps1
- generate_ssas_model.py
- 4. Modèle de données de l'entrepôt (CH_DWH)
- DWH Suisse : ponctualité des transports publics suisses
- 6. Le cube SSAS Tabular `DWH_Suisse_Cube`
- Rapport proposé : 4 pages
- Bonnes pratiques déjà appliquées
- 1. Passages réels : *Ist-Daten*
- 2. Architecture expliquée simplement
- CLAUDE.md
- tools/README.md

## God Nodes (most connected - your core abstractions)
1. `gid()` - 17 edges
2. `a()` - 15 edges
3. `1. Installation pas à pas` - 14 edges
4. `child_package()` - 13 edges
5. `Erreurs courantes et solutions` - 13 edges
6. `sql_task()` - 12 edges
7. `pkg_00_master()` - 12 edges
8. `Roadmap : de l'installation au rapport Power BI` - 11 edges
9. `11. Exercices pour monter en compétence` - 11 edges
10. `data_flow()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `write()` --calls--> `os`  [EXTRACTED]
  tools/generate_ssis.py →   _Bridges community 0 → community 9_
- `pkg_00_master()` --calls--> `Pkg`  [EXTRACTED]
  tools/generate_ssis.py → tools/generate_ssis.py  _Bridges community 1 → community 0_

## Import Cycles
- None detected.

## Communities (20 total, 5 thin omitted)

### Community 0 - "generate_ssis.py"
Cohesion: 0.12
Nodes (31): a(), chain(), cm_id(), conmgr_xml(), constraint(), data_flow(), err_cols(), ff_col() (+23 more)

### Community 1 - "child_package"
Cohesion: 0.18
Nodes (12): all_packages(), child_package(), Pkg, pkg_10_ext(), body(), pkg_20_ods_servicepoints(), pkg_21_ods_istdaten(), pkg_22_ods_meteo() (+4 more)

### Community 2 - "5. Le projet SSIS `DWH_Suisse_ETL`"
Cohesion: 0.12
Nodes (17): `10_EXT_Telechargement` : extraction, `20_ODS_ServicePoints` : premier Data Flow, `21_ODS_Istdaten` : boucle sur fichiers, `22_ODS_Meteo` : JSON sans composant payant, `30_STG_Preparation`, `40_DWH_Dimensions`, `41_DWH_Faits`, `50_SSAS_Traitement` (+9 more)

### Community 4 - "Erreurs courantes et solutions"
Cohesion: 0.12
Nodes (16): 8. Exploitation et dépannage, Avertissement « external metadata column ... out of synchronization », `Cannot bulk load because the file ... could not be opened. Operating system error code 5`, Erreur de certificat avec SSMS ou PowerShell, Erreur de troncature dans un Data Flow, Erreurs courantes et solutions, Le cube ne se déploie ou ne se traite pas, Le disque se remplit (+8 more)

### Community 5 - "1. Installation pas à pas"
Cohesion: 0.14
Nodes (14): 1. Installation pas à pas, Pré-requis matériel, Vue d'ensemble, Étape 10 : premier chargement avec SSIS, Étape 11 : créer le cube et ouvrir Power BI, Étape 1 : SQL Server 2022 Developer, Étape 2 : SSMS, Étape 3 : pilote Microsoft OLE DB 18 pour SQL Server (+6 more)

### Community 6 - "11. Exercices pour monter en compétence"
Cohesion: 0.18
Nodes (11): 11. Exercices pour monter en compétence, Exercice 10 ⭐ : tableau de bord d'exploitation, Exercice 1 ⭐ : premier package de A à Z, Exercice 2 ⭐ : paramètre et expression, Exercice 3 ⭐⭐ : nouvelle règle de qualité, Exercice 4 ⭐⭐ : simuler un changement SCD2, Exercice 5 ⭐⭐⭐ : dimension en Data Flow pur (sans procédure), Exercice 6 ⭐⭐ : l'assistant SCD de SSIS (+3 more)

### Community 7 - "Roadmap : de l'installation au rapport Power BI"
Cohesion: 0.18
Nodes (11): Phase 0 : installation, Phase 1 : créer les bases et comprendre l'ODS, Phase 2 : comprendre et exécuter les packages SSIS, Phase 3 : zone de préparation (STG) et qualité des données, Phase 4 : l'entrepôt (DWH), le modèle en étoile et l'historisation, Phase 5 : industrialiser (déploiement et planification), Phase 6 : le cube SSAS Tabular, Phase 7 : le rapport Power BI (+3 more)

### Community 8 - "Common.ps1"
Cohesion: 0.42
Nodes (4): Get-WebPage(), Initialize-Log(), Save-WebFile(), Write-Log()

### Community 10 - "4. Modèle de données de l'entrepôt (CH_DWH)"
Cohesion: 0.22
Nodes (9): 4. Modèle de données de l'entrepôt (CH_DWH), Couche de vues `cube.*`, Dictionnaire des dimensions, Grain des tables de faits, Le principe du « modèle en étoile », Ligne « Inconnu » (clé -1), Membres déduits (*inferred members*), Règles de calcul des indicateurs (+1 more)

### Community 11 - "DWH Suisse : ponctualité des transports publics suisses"
Cohesion: 0.22
Nodes (9): Ce qui rend ce projet « réaliste », DWH Suisse : ponctualité des transports publics suisses, Démarrage rapide (résumé), Le projet en une image, Licence des données, Pour qui, et comment lire ce dépôt ?, Structure du dépôt, Toute la documentation (+1 more)

### Community 12 - "6. Le cube SSAS Tabular `DWH_Suisse_Cube`"
Cohesion: 0.25
Nodes (8): 6. Le cube SSAS Tabular `DWH_Suisse_Cube`, Contenu du modèle, Déployer le cube, Les mesures (indicateurs), Pour aller plus loin, Qu'est-ce qu'un « cube » tabulaire ?, Sécurité : rôles, Zoom sur une mesure avancée : ponctualité sous la pluie

### Community 13 - "Rapport proposé : 4 pages"
Cohesion: 0.25
Nodes (8): 7. Le rapport Power BI, Enregistrer, Page 1 : Vue d'ensemble, Page 2 : Carte, Page 3 : Opérateurs et lignes, Page 4 : Météo et ponctualité, Rapport proposé : 4 pages, Se connecter au cube (connexion active)

### Community 14 - "Bonnes pratiques déjà appliquées"
Cohesion: 0.25
Nodes (8): 10. Bonnes pratiques, Architecture, Bonnes pratiques de l'entreprise, Bonnes pratiques déjà appliquées, Projet et Git, SQL, SSIS, Écarts connus (à traiter)

### Community 15 - "1. Passages réels : *Ist-Daten*"
Cohesion: 0.29
Nodes (7): 1. Passages réels : *Ist-Daten*, 2. Référentiel des points d'arrêt (*Service Points*), 3. Les sources de données, 3. Météo : Open-Meteo, Autres pièges gérés, Le statut de l'heure réelle : un piège important, Les 22 colonnes

### Community 16 - "2. Architecture expliquée simplement"
Cohesion: 0.33
Nodes (6): 2. Architecture expliquée simplement, L'analogie de l'entrepôt logistique, Le flux complet, Les choix techniques, et pourquoi, Pourquoi plusieurs couches ? (questions fréquentes), Reprise après incident (robustesse)

## Knowledge Gaps
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `5. Le projet SSIS `DWH_Suisse_ETL`` connect `5. Le projet SSIS `DWH_Suisse_ETL`` to `README.md`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Should `generate_ssis.py` be split into smaller, more focused modules?**
  _Cohesion score 0.11733615221987315 - nodes in this community are weakly interconnected._
- **Why does `8. Exploitation et dépannage` connect `Erreurs courantes et solutions` to `README.md`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Should `5. Le projet SSIS `DWH_Suisse_ETL`` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Why does `1. Installation pas à pas` connect `1. Installation pas à pas` to `README.md`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Should `Erreurs courantes et solutions` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._
- **Should `1. Installation pas à pas` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._