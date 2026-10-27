# 7. Le rapport Power BI

## Se connecter au cube (connexion active)

1. Power BI Desktop > **Obtenir les données** > **Base de données Analysis Services**.
2. Serveur : `localhost` ; Base de données : `DWH_Suisse_Cube`.
3. Mode : **Se connecter en direct** (*Connect live*).
4. Les tables et mesures du cube apparaissent dans le volet *Données*.

> **Connexion active ou importation ?** En connexion active, Power BI **n'a pas de copie** des données : il interroge le cube à chaque clic. Les formules (mesures) restent celles du cube : tout le monde utilise la même définition de la ponctualité. C'est le mode privilégié en entreprise quand un cube existe.

## Rapport proposé : 4 pages

### Page 1 : Vue d'ensemble

| Visuel | Champs |
|---|---|
| 4 cartes (KPI) | `Taux de ponctualité`, `Retard moyen (min)`, `Taux de suppression`, `Nb passages` |
| Courbe | Axe : `Date[Date]` ; valeurs : `Taux de ponctualité` et `Taux de ponctualité J-7` |
| Histogramme | Axe : `Heure[Heure]` ; valeur : `Taux de ponctualité` (les heures de pointe ressortent) |
| Segments | `Mode de transport[Mode]`, `Canton[Région linguistique]`, `Date[Type de jour]` |

### Page 2 : Carte

| Visuel | Champs |
|---|---|
| Carte (Map ou Azure Map) | Latitude/Longitude : `Gare[Latitude]`, `Gare[Longitude]` ; taille : `Nb passages` ; couleur : `Taux de ponctualité` |
| Tableau | `Gare[Gare]`, `Canton[Canton]`, `Nb passages mesurés`, `Taux de ponctualité`, `Retard cumulé (h)`, trié par retard cumulé décroissant |

Astuce : filtrez `Gare[Pays] = CH` et `Nb passages > 500` pour garder les arrêts significatifs.

### Page 3 : Opérateurs et lignes

| Visuel | Champs |
|---|---|
| Barres horizontales | `Opérateur[Opérateur]` × `Taux de ponctualité` (top 15 par nb de passages) |
| Matrice | Lignes : `Ligne[Type de service]` > `Ligne[Ligne (libellé)]` ; valeurs : `Nb trajets`, `Taux de ponctualité`, `Nb suppressions` |
| Nuage de points | X : `Nb passages` ; Y : `Retard moyen (min)` ; détails : `Ligne[Ligne (libellé)]` |

### Page 4 : Météo et ponctualité

| Visuel | Champs |
|---|---|
| 2 cartes | `Taux de ponctualité - heures sèches` et `Taux de ponctualité - heures pluvieuses` |
| Graphique combiné | Axe : `Date[Date]` ; colonnes : `Précipitations (mm)` ; ligne : `Taux de ponctualité` |
| Matrice | Lignes : `Canton[Canton]` ; valeurs : `Heures pluvieuses`, `Température moyenne (°C)`, les deux taux de ponctualité |

## Enregistrer

Enregistrez le fichier sous `powerbi\DWH_Suisse.pbix`, puis poussez-le sur GitHub :

```bash
git add powerbi/DWH_Suisse.pbix
git commit -m "Ajout du rapport Power BI"
git push
```

> Le `.pbix` en connexion active est léger (aucune donnée embarquée) : il se versionne sans problème.
