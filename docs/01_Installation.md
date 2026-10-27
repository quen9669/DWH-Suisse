# 1. Installation pas à pas

Durée : **1 h 30 à 2 h** (surtout des téléchargements). Tous les logiciels sont **gratuits**.

## Pré-requis matériel

| Élément | Minimum | Conseillé |
|---|---|---|
| Système | Windows 10/11 64 bits | Windows 11 |
| Mémoire vive | 8 Go | 16 Go (SQL Server + SSAS + Visual Studio en même temps) |
| Disque libre | 20 Go | 40 Go (chaque jour de données ≈ 0,5 Go de CSV + ~0,3 Go en base) |
| Connexion Internet | Oui | Fibre (un fichier de passages ≈ 300 à 500 Mo) |

## Vue d'ensemble

| # | Logiciel | À quoi il sert | Licence |
|---|---|---|---|
| 1 | SQL Server 2022 **Developer** | Bases de données + moteur SSIS + moteur SSAS | Gratuit (pour développer, pas pour la production) |
| 2 | SSMS | Explorer les bases, lancer des requêtes | Gratuit |
| 3 | Pilote OLE DB 18 | Permet à SSIS et SSAS de se connecter à SQL Server | Gratuit |
| 4 | Visual Studio 2022 Community | Concevoir les packages SSIS et le cube | Gratuit (usage individuel/formation) |
| 5 | Extensions SSIS et Analysis Services | Ajoutent les types de projets SSIS et SSAS à Visual Studio | Gratuit |
| 6 | Power BI Desktop | Rapports | Gratuit |
| 7 | Git | Récupérer le projet depuis GitHub | Gratuit |

> 💡 **Versions plus récentes** : SQL Server 2025 et Visual Studio 2026 existent aussi et fonctionnent avec les extensions récentes. Ce guide utilise le couple **2022**, le plus éprouvé. Si vous prenez SQL Server 2025, changez la cible du projet SSIS : *Propriétés du projet > Configuration Properties > General > TargetServerVersion*.

---

## Étape 1 : SQL Server 2022 Developer

1. Cherchez « **SQL Server downloads** » sur le site de Microsoft, puis téléchargez l'édition **Developer**.
2. Lancez l'installeur et choisissez **Custom** (personnalisée).
3. Dans *SQL Server Installation Center*, choisissez *New SQL Server standalone installation*.
4. **Édition** : *Developer*.
5. **Fonctionnalités** (*Feature Selection*), cochez :
   - ✅ **Database Engine Services**
   - ✅ **Analysis Services**
   - ✅ **Integration Services**
   - (le reste n'est pas nécessaire)
6. **Instance** : *Default instance* (nom `MSSQLSERVER`). Tout le projet suppose `localhost`.
7. **Server Configuration** : passez *SQL Server Agent* en démarrage **Automatic** (utile en phase 5).
8. **Database Engine Configuration** : *Windows authentication mode*, puis cliquez sur **Add Current User**.
9. **Analysis Services Configuration** :
   - Server Mode : **Tabular Mode** ⚠️ (important : le cube du projet est tabulaire)
   - Cliquez sur **Add Current User**
10. Terminez l'installation, puis redémarrez le PC si on vous le demande.

## Étape 2 : SSMS

Cherchez « **Download SQL Server Management Studio** », puis installez la dernière version.

Test : ouvrez SSMS, *Server name* = `localhost`, *Authentication* = Windows, puis cliquez sur *Connect*. Si la connexion échoue avec une erreur de certificat, cochez **Trust server certificate**.

## Étape 3 : pilote Microsoft OLE DB 18 pour SQL Server

Cherchez « **Microsoft OLE DB Driver 18 for SQL Server** », puis installez la version x64.

> Les connexions SSIS du projet utilisent le fournisseur `MSOLEDBSQL.1`, c'est-à-dire la version 18. Si vous n'avez que la version 19, voir [Dépannage](08_Exploitation_et_depannage.md#le-fournisseur-msoledbsql1-nest-pas-inscrit).

## Étape 4 : Visual Studio 2022 Community

1. Téléchargez **Visual Studio 2022 Community**.
2. Dans l'installeur, la charge de travail **« Développement .NET Desktop »** suffit. Les extensions BI s'installent ensuite.

## Étape 5 : extensions SSIS et Analysis Services

Dans Visual Studio : menu **Extensions > Manage Extensions**, puis cherchez et installez :

- **SQL Server Integration Services Projects 2022** (ou 2022+)
- **Microsoft Analysis Services Projects 2022** (ou 2022+)

Fermez Visual Studio pour lancer l'installation, puis rouvrez-le.

> Si l'installation de l'extension SSIS échoue, téléchargez son installeur `.exe` depuis le *Visual Studio Marketplace* et lancez-le, Visual Studio étant fermé.

## Étape 6 : Power BI Desktop

Installez-le depuis le **Microsoft Store** : il se mettra à jour tout seul.

## Étape 7 : Git et récupération du projet

1. Installez **Git for Windows** (options par défaut).
2. Ouvrez un terminal et clonez le dépôt **exactement à cet endroit** (les chemins par défaut du projet en dépendent) :

```bash
git clone https://github.com/quen9669/DWH-Suisse C:\DWH_Suisse\DWH-Suisse
```

> Vous voulez un autre emplacement ? C'est possible : il faudra alors modifier les paramètres `ScriptsFolder` et `DataFolder` dans `Project.params` (voir [05_Packages_SSIS.md](05_Packages_SSIS.md#paramètres-du-projet)).

---

## Étape 8 : préparer le PC

Ouvrez **PowerShell en administrateur** (menu Démarrer > tapez *PowerShell* > clic droit > *Exécuter en tant qu'administrateur*) :

```powershell
cd C:\DWH_Suisse\DWH-Suisse\scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\Initialize-Environment.ps1
```

Ce script :
1. vérifie que les services SQL Server, Analysis Services et SQL Agent sont installés ;
2. crée `C:\DWH_Suisse\data\` et ses sous-dossiers (`istdaten`, `servicepoints`, `meteo`, `archive`, `logs`) ;
3. donne aux comptes de service SQL Server le droit d'y accéder (SQL Server lit lui-même les fichiers météo) ;
4. installe le module PowerShell **SqlServer**.

Résultat attendu :

```
=== 1. Services installés ===
  [OK]      MSSQLSERVER              Running - Moteur SQL Server (bases de données)
  [OK]      SQLSERVERAGENT           Running - SQL Server Agent (planification)
  [OK]      MSSQLServerOLAPService   Running - Analysis Services (cube)
  ...
```

## Étape 9 : créer les bases de données

Toujours dans PowerShell :

```powershell
.\Deploy-Database.ps1
```

Le script exécute `sql\01` à `sql\09` dans l'ordre. Vous devez voir défiler `01 - Bases et schémas : OK` jusqu'à `09 - Sécurité : OK`.

> **Alternative manuelle** : dans SSMS, ouvrez chaque fichier `sql\0X_*.sql` dans l'ordre et appuyez sur **F5**.

---

## Étape 10 : premier chargement avec SSIS

1. Dans Visual Studio : **Fichier > Ouvrir > Projet/Solution**, puis choisissez `C:\DWH_Suisse\DWH-Suisse\ssis\DWH_Suisse_ETL\DWH_Suisse_ETL.dtproj`.
2. Dans l'*Explorateur de solutions*, double-cliquez sur **Project.params** et vérifiez les chemins.
3. Clic droit sur **00_MASTER.dtsx**, puis **Execute Package**.
4. Patientez. Avec 3 jours de données, comptez 10 à 30 minutes (surtout le téléchargement).
   - vert ✅ = étape réussie, rouge ❌ = erreur (onglet *Progress* pour le détail)
5. Vérifiez dans SSMS :

```sql
SELECT * FROM CH_ADMIN.etl.vw_Suivi_Lots;   -- le lot doit être en "Succès"
SELECT COUNT_BIG(*) FROM CH_DWH.fact.StopEvent;
```

> 💾 Pour une première découverte, vous pouvez réduire le volume : paramètre de projet `NbJoursIstdaten` = `1`.

## Étape 11 : créer le cube et ouvrir Power BI

Voir [06_Cube_SSAS.md](06_Cube_SSAS.md#déployer-le-cube) puis [07_Power_BI.md](07_Power_BI.md).

---

**Un problème ?** Consultez [08_Exploitation_et_depannage.md](08_Exploitation_et_depannage.md) : les erreurs les plus probables y sont listées avec leur solution.
