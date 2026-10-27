# 3. Les sources de données

Trois sources, trois formats différents : c'est voulu, pour pratiquer.

| Source | Format | Volume | Fréquence | Package |
|---|---|---|---|---|
| Passages réels (*Ist-Daten*) | CSV `;`, UTF-8 | ~2,5 millions de lignes, 300 à 500 Mo par jour | 1 fichier par jour | `21_ODS_Istdaten` |
| Référentiel des points d'arrêt | CSV `;` dans un ZIP | ~60 000 lignes, 55 colonnes | photo complète | `20_ODS_ServicePoints` |
| Météo horaire | JSON (API REST) | 24 heures × 26 cantons par jour | 1 appel par canton et par jour | `22_ODS_Meteo` |

---

## 1. Passages réels : *Ist-Daten*

- **Producteur** : plateforme open data des transports publics suisses (opentransportdata.swiss)
- **Page** : https://data.opentransportdata.swiss/dataset/ist-daten-v2
- **Documentation** : https://opentransportdata.swiss/en/cookbook/actual-data/
- **Contenu** : pour **chaque trajet** de chaque transport public (train, bus, tram, bateau, funiculaire...) et **chaque arrêt desservi**, l'heure prévue et l'heure réelle d'arrivée et de départ.
- **Disponibilité** : environ les **50 derniers jours** en ligne. Les plus anciens sont dans les archives mensuelles (voir la phase 9 de la roadmap).

### Les 22 colonnes

| Colonne | Signification | Exemple |
|---|---|---|
| `BETRIEBSTAG` | Jour d'exploitation | `25.10.2026` |
| `FAHRT_BEZEICHNER` | Identifiant du trajet (se répète chaque jour) | `80:07____:3292:000` |
| `BETREIBER_ID` / `_ABK` / `_NAME` | Opérateur | `SBB` / Chemins de fer fédéraux |
| `PRODUKT_ID` | Mode de transport (en allemand) | `Zug` (train), `Bus`, `Tram`, `Schiff` (bateau) |
| `LINIEN_ID` / `LINIEN_TEXT` | N° / libellé de ligne | `IC1`, `31` |
| `UMLAUF_ID` | Roulement (véhicule) | |
| `VERKEHRSMITTEL_TEXT` | Type de service | `IC`, `IR`, `RE`, `S`, `B` |
| `ZUSATZFAHRT_TF` | Trajet supplémentaire ? | `true` / `false` |
| `FAELLT_AUS_TF` | Trajet supprimé ? | `true` / `false` |
| `BPUIC` | N° officiel de l'arrêt (clé vers le référentiel) | `8503000` (Zurich HB) |
| `HALTESTELLEN_NAME` | Nom de l'arrêt | `Zürich HB` |
| `ANKUNFTSZEIT` | Arrivée **prévue** | `25.10.2026 22:34` |
| `AN_PROGNOSE` | Arrivée **réelle ou prévue** | `25.10.2026 22:35:12` |
| `AN_PROGNOSE_STATUS` | Qualité de l'heure réelle | voir ci-dessous |
| `ABFAHRTSZEIT`, `AB_PROGNOSE`, `AB_PROGNOSE_STATUS` | Idem pour le départ | |
| `DURCHFAHRT_TF` | Passage sans arrêt ? | `false` |
| `SLOID` | Identifiant suisse de l'arrêt | `ch:1:sloid:3000` |

### Le statut de l'heure réelle : un piège important

| Statut | Signification | Utilisé pour la ponctualité ? |
|---|---|---|
| `REAL` | Heure réellement mesurée | ✅ oui |
| `GESCHAETZT` | Heure estimée | ✅ oui |
| `PROGNOSE` (ou vide) | Ce n'est qu'une **prévision** | ❌ non |
| `UNBEKANNT` | Aucune information | ❌ non |

👉 Un retard calculé sur une prévision n'est pas un vrai retard. C'est pourquoi le projet distingue les passages **mesurés** des autres (colonne `MeasuredCount`).

### Autres pièges gérés

- Les horaires d'arrivée ont une précision à la minute, les horaires réels à la seconde.
- Le premier arrêt d'un trajet n'a pas d'arrivée, et le dernier n'a pas de départ (statut `SANS_OBJET`).
- Le fichier contient aussi des arrêts **étrangers** (trains allemands, italiens...) : ils deviennent des **membres déduits** de la dimension Gare, en canton « Inconnu / étranger ».
- Des valeurs aberrantes existent (retards de plusieurs jours) : au-delà de 6 h de retard ou de 30 min d'avance, la ligne est marquée `IsDelayOutlier` et exclue des indicateurs.

## 2. Référentiel des points d'arrêt (*Service Points*)

- **Page** : https://data.opentransportdata.swiss/dataset/service-points-actual-date
- **Contenu** : tous les points d'arrêt connus (gares, arrêts de bus, débarcadères...) avec le nom officiel, le canton, la commune, les coordonnées GPS, l'altitude et le gestionnaire.
- **Lien avec les passages** : colonne `number` = `BPUIC` des passages.
- Fichier en **UTF-8 avec BOM** (marque d'encodage en début de fichier), 55 colonnes. Le script vérifie ce nombre et s'arrête si le format change.

Colonnes utilisées par l'entrepôt : `number`, `sloid`, `designationOfficial`, `abbreviation`, `isoCountryCode`, `cantonName`, `cantonAbbreviation`, `districtName`, `municipalityName`, `localityName`, `meansOfTransport`, `stopPoint`, `businessOrganisationAbbreviationFr`, `businessOrganisationDescriptionFr`, `wgs84North`, `wgs84East`, `height`. Toutes les autres colonnes restent dans l'ODS, au cas où.

## 3. Météo : Open-Meteo

- **Site** : https://open-meteo.com (gratuit, sans inscription, sans clé)
- **Appel** (exemple pour Zurich le 25/10/2026) :
  ```
  https://api.open-meteo.com/v1/forecast?latitude=47.3769&longitude=8.5417
      &start_date=2026-10-25&end_date=2026-10-25
      &hourly=temperature_2m,precipitation,snowfall,wind_speed_10m
      &timezone=Europe%2FZurich
  ```
- **Réponse** : des tableaux « parallèles » (la 8e heure correspond à la 8e température, à la 8e valeur de pluie...) :
  ```json
  { "hourly": {
      "time":           ["2026-10-25T00:00", "2026-10-25T01:00", ...],
      "temperature_2m": [8.1, 7.9, ...],
      "precipitation":  [0.0, 0.2, ...] } }
  ```
- **Point de mesure** : le chef-lieu de chaque canton (fichier `scripts\ref\cantons.csv`, repris dans `dim.Canton`).
- **Piège géré** : le jour du passage à l'heure d'hiver, la même heure locale apparaît deux fois. La STG fait la moyenne (température) ou la somme (pluie).
