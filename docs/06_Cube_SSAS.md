# 6. Le cube SSAS Tabular `DWH_Suisse_Cube`

## Qu'est-ce qu'un « cube » tabulaire ?

C'est une **copie compressée en mémoire** de l'entrepôt, organisée pour l'analyse :
- les tables portent des **noms métier en français** (« Gare », « Passages », « Taux de ponctualité ») ;
- les **formules officielles** des indicateurs (mesures DAX) sont définies **une seule fois** ;
- Power BI, Excel ou tout autre outil s'y connecte et obtient des réponses en quelques millisecondes.

## Contenu du modèle

| Table | Type | Source (vue SQL) | Visible |
|---|---|---|---|
| Date | Dimension (marquée « table de dates ») | `cube.vw_Date` | ✅ |
| Heure | Dimension | `cube.vw_Heure` | ✅ |
| Canton | Dimension | `cube.vw_Canton` | ✅ |
| Gare | Dimension | `cube.vw_Gare` | ✅ |
| Opérateur | Dimension | `cube.vw_Operateur` | ✅ |
| Ligne | Dimension | `cube.vw_Ligne` | ✅ |
| Mode de transport | Dimension | `cube.vw_Mode` | ✅ |
| Statut arrivée / Statut départ | Dimension (même source, 2 rôles) | `cube.vw_StatutMesure` | ✅ |
| **Passages** | Faits | `cube.vw_Passage` | mesures seulement |
| **Météo** | Faits | `cube.vw_Meteo` | mesures seulement |

**Hiérarchies** : Calendrier (Année > Mois > Date), Journée (Tranche horaire > Heure > Horaire), Géographie (Région linguistique > Canton), Modes (Catégorie > Mode).

Les clés techniques (`DateKey`, `StationKey`...) sont **masquées** : l'utilisateur ne voit que des libellés.

## Les mesures (indicateurs)

| Dossier | Mesure | Définition simple |
|---|---|---|
| 1. Volumes | Nb passages | Nombre de passages planifiés |
| | Nb trajets | Nombre de trajets distincts (calcul jour par jour) |
| | Nb passages mesurés | Passages dont on connaît l'heure réelle |
| 2. Ponctualité | Nb passages ponctuels | Mesurés et moins de 3 min de retard |
| | **Taux de ponctualité** | Ponctuels ÷ mesurés |
| | Taux de ponctualité J-7 | Même chose 7 jours avant (`DATEADD`) |
| | Évolution ponctualité vs J-7 | Différence en points |
| 3. Retards | Retard moyen (min) | Moyenne des retards mesurés |
| | Retard max (min) | Plus gros retard |
| | Retard cumulé (h) | Somme des retards (sans les avances) |
| | Nb passages retard ≥ 5 min | |
| 4. Suppressions | Nb suppressions, Taux de suppression | Trajets annulés |
| 5. Météo croisée | Taux de ponctualité - heures pluvieuses / sèches | Voir ci-dessous |
| Météo | Température moyenne, Précipitations, Neige, Vent moyen, Heures pluvieuses | |

### Zoom sur une mesure avancée : ponctualité sous la pluie

```dax
Taux de ponctualité - heures pluvieuses :=
VAR HeuresPluie =
    CALCULATETABLE (
        SUMMARIZE ( 'Météo', 'Météo'[DateKey], 'Météo'[TimeKey], 'Météo'[CantonKey] ),
        'Météo'[IsWetHour] = 1
    )
RETURN
    CALCULATE (
        [Taux de ponctualité],
        TREATAS ( HeuresPluie, 'Passages'[DateKey], 'Passages'[HourKey], 'Passages'[CantonKey] )
    )
```

En clair :
1. on liste les combinaisons (jour, heure, canton) où il a plu ;
2. `TREATAS` applique cette liste comme un filtre sur les passages, sans relation physique entre les deux tables de faits ;
3. on calcule la ponctualité de ces seuls passages.

## Sécurité : rôles

| Rôle | Droits |
|---|---|
| `Lecteurs` | Lecture de tout le modèle |
| `Lecteurs Suisse romande` | Exemple de **sécurité par ligne (RLS)** : filtre `'Canton'[Région linguistique] = "Suisse romande"`. Ces lecteurs ne voient que les passages et la météo des cantons romands. |

Pour ajouter des membres : *Model > Roles* (ou *Extensions > Model > Roles*), onglet *Members*.

## Déployer le cube

1. Ouvrez `ssas\DWH_Suisse_Cube\DWH_Suisse_Cube.smproj` dans Visual Studio.
2. À la première ouverture, Visual Studio demande un **serveur d'espace de travail** : choisissez **Integrated workspace**.
3. Vérifiez la connexion : *Tabular Model Explorer > Data Sources > CH_DWH*. Le serveur est `localhost`.
4. Clic droit sur le projet > **Properties** : *Deployment Server* = `localhost`, *Database* = `DWH_Suisse_Cube`.
5. Clic droit sur le projet > **Deploy**. Le déploiement crée le modèle **et** le traite (charge les données).
6. Contrôle : SSMS > *Connect* > *Analysis Services* > `localhost`. La base `DWH_Suisse_Cube` apparaît.
7. Dans le projet SSIS, passez le paramètre `TraiterCube` à `true` : le master package rechargera le cube à chaque exécution.

> **Compte de service** : lors d'un traitement sur le serveur, c'est le compte `NT SERVICE\MSSQLServerOLAPService` qui lit `CH_DWH` (mode *impersonateServiceAccount*). Le script `sql\09_Securite.sql` lui donne ce droit.

## Pour aller plus loin

- **Partitions** : découper la table Passages par mois et ne retraiter que le mois courant (exercice 8).
- **Perspectives** : créer une vue simplifiée « Ponctualité » ne montrant que les tables utiles.
- **Traductions** : ajouter l'allemand (*Model > Translations*), un classique en Suisse.
- **Tabular Editor** (gratuit, version 2) et **DAX Studio** (gratuit) : outils incontournables pour travailler un modèle tabulaire.
