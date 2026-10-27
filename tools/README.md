# Outils de génération

| Script | Produit |
|---|---|
| `generate_ssis.py` | Le projet SSIS complet : `ssis/DWH_Suisse_ETL/*.dtsx`, `*.conmgr`, `Project.params`, `.dtproj` |
| `generate_ssas_model.py` | Le modèle tabulaire `ssas/DWH_Suisse_Cube/Model.bim` et le `.smproj` |

**Vous n'avez pas besoin de les exécuter** : les fichiers générés sont déjà dans le dépôt.

⚠️ Relancer un générateur **écrase** les fichiers produits, y compris vos modifications faites dans Visual Studio. Une fois le projet ouvert et modifié dans Visual Studio, c'est **Visual Studio qui fait foi**.

Pourquoi des générateurs ? Les packages SSIS sont des fichiers XML très verbeux (un Data Flow de 55 colonnes représente des milliers de lignes de XML). Les générer garantit des noms, des descriptions et des identifiants cohérents. En entreprise, des outils comme **Biml** reposent sur la même idée.

Usage (Python 3.10+) :

```bash
python tools/generate_ssis.py
python tools/generate_ssas_model.py
```
