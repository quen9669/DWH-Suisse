"""
Générateur du modèle SSAS Tabular (ssas/DWH_Suisse_Cube/Model.bim + .smproj).

Comme pour generate_ssis.py : vous n'avez PAS besoin de l'exécuter, les
fichiers sont déjà dans le dépôt. Le relancer ÉCRASE Model.bim (y compris
les modifications faites dans Visual Studio).

Usage :  python tools/generate_ssas_model.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ssas", "DWH_Suisse_Cube")
DS = "CH_DWH"


def col(name, source, dtype, hidden=False, fmt=None, sort_by=None, key=False, category=None, summarize="none",
        description=None):
    c = {"name": name, "dataType": dtype, "sourceColumn": source, "summarizeBy": summarize}
    if hidden:
        c["isHidden"] = True
    if fmt:
        c["formatString"] = fmt
    if sort_by:
        c["sortByColumn"] = sort_by
    if key:
        c["isKey"] = True
    if category:
        c["dataCategory"] = category
    if description:
        c["description"] = description
    return c


def table(name, view, columns, description, measures=None, hierarchies=None, category=None):
    t = {
        "name": name,
        "description": description,
        "columns": columns,
        "partitions": [{
            "name": name,
            "dataView": "full",
            "source": {"type": "query", "query": f"SELECT * FROM {view}", "dataSource": DS},
        }],
    }
    if category:
        t["dataCategory"] = category
    if measures:
        t["measures"] = measures
    if hierarchies:
        t["hierarchies"] = hierarchies
    return t


def measure(name, expr, fmt, folder, description):
    return {"name": name, "expression": expr, "formatString": fmt, "displayFolder": folder,
            "description": description}


def hierarchy(name, levels):
    return {"name": name, "levels": [{"name": lv, "ordinal": i, "column": lv} for i, lv in enumerate(levels)]}


INT, STR, BOOL, DEC, DT = "int64", "string", "boolean", "decimal", "dateTime"

tables = [
    table("Date", "cube.vw_Date", [
        col("DateKey", "DateKey", INT, hidden=True),
        col("Date", "Date", DT, fmt="dd/mm/yyyy", key=True),
        col("Année", "Year", INT),
        col("Trimestre n°", "Quarter", INT, hidden=True),
        col("Trimestre (tri)", "YearQuarter", INT, hidden=True),
        col("Trimestre", "QuarterLabel", STR, sort_by="Trimestre (tri)"),
        col("Mois n°", "Month", INT, hidden=True),
        col("Mois", "MonthName", STR, sort_by="Mois n°"),
        col("Année-Mois (tri)", "YearMonth", INT, hidden=True),
        col("Année-Mois", "YearMonthLabel", STR, sort_by="Année-Mois (tri)"),
        col("Semaine ISO", "IsoWeek", INT),
        col("Jour du mois", "DayOfMonth", INT),
        col("Jour de la semaine n°", "DayOfWeek", INT, hidden=True),
        col("Jour de la semaine", "DayName", STR, sort_by="Jour de la semaine n°"),
        col("Week-end", "IsWeekend", BOOL),
        col("Férié", "IsHoliday", BOOL),
        col("Nom du jour férié", "HolidayName", STR),
        col("Type de jour", "DayType", STR, description="Jour ouvrable / Samedi / Dimanche ou férié"),
    ], "Calendrier (jour d'exploitation des transports).",
        hierarchies=[hierarchy("Calendrier", ["Année", "Mois", "Date"])], category="Time"),

    table("Heure", "cube.vw_Heure", [
        col("TimeKey", "TimeKey", INT, hidden=True),
        col("Heure n°", "Hour", INT, hidden=True),
        col("Minute", "Minute", INT, hidden=True),
        col("Heure", "HourLabel", STR),
        col("Horaire", "TimeLabel", STR),
        col("Tranche horaire (tri)", "TimeBandOrder", INT, hidden=True),
        col("Tranche horaire", "TimeBand", STR, sort_by="Tranche horaire (tri)"),
    ], "Heure prévue du passage (à la minute) ; heure pleine pour la météo.",
        hierarchies=[hierarchy("Journée", ["Tranche horaire", "Heure", "Horaire"])]),

    table("Canton", "cube.vw_Canton", [
        col("CantonKey", "CantonKey", INT, hidden=True),
        col("Canton (abr.)", "CantonAbbr", STR, category="StateOrProvince"),
        col("Canton", "CantonName", STR),
        col("Chef-lieu", "Capital", STR, category="City"),
        col("Région linguistique", "LanguageRegion", STR),
        col("Latitude", "Latitude", DEC, category="Latitude", hidden=True),
        col("Longitude", "Longitude", DEC, category="Longitude", hidden=True),
    ], "Canton suisse de l'arrêt (Inconnu / étranger = arrêt hors de Suisse).",
        hierarchies=[hierarchy("Géographie", ["Région linguistique", "Canton"])]),

    table("Gare", "cube.vw_Gare", [
        col("StationKey", "StationKey", INT, hidden=True),
        col("UIC", "Uic", INT, description="Numéro officiel de l'arrêt"),
        col("Gare", "StationName", STR),
        col("Gare (libellé)", "StationLabel", STR),
        col("Abréviation", "Abbreviation", STR),
        col("Pays", "CountryIso", STR, category="Country"),
        col("Commune", "MunicipalityName", STR, category="City"),
        col("District", "DistrictName", STR),
        col("Moyens de transport", "MeansOfTransport", STR),
        col("Gestionnaire", "OwnerAbbr", STR),
        col("Latitude", "Latitude", DEC, category="Latitude"),
        col("Longitude", "Longitude", DEC, category="Longitude"),
        col("Altitude (m)", "Altitude", DEC),
        col("Arrêt déduit", "IsInferred", BOOL,
            description="Vrai = arrêt vu dans les passages mais absent du référentiel"),
        col("Valide du", "ValidFrom", DT, fmt="dd/mm/yyyy"),
        col("Valide jusqu'au", "ValidTo", DT, fmt="dd/mm/yyyy"),
        col("Version courante", "IsCurrent", BOOL),
    ], "Points d'arrêt (gares, arrêts de bus...) - historisés (SCD type 2)."),

    table("Opérateur", "cube.vw_Operateur", [
        col("OperatorKey", "OperatorKey", INT, hidden=True),
        col("Opérateur", "OperatorAbbr", STR),
        col("Nom de l'opérateur", "OperatorName", STR),
    ], "Entreprise de transport (CFF/SBB, BLS, CarPostal...)."),

    table("Ligne", "cube.vw_Ligne", [
        col("LineKey", "LineKey", INT, hidden=True),
        col("Ligne", "LineCode", STR),
        col("Type de service", "ServiceType", STR, description="IC, IR, RE, S, B (bus)..."),
        col("Ligne (libellé)", "LineLabel", STR),
    ], "Ligne commerciale (par opérateur et mode)."),

    table("Mode de transport", "cube.vw_Mode", [
        col("TransportModeKey", "TransportModeKey", INT, hidden=True),
        col("Mode", "ModeLabel", STR),
        col("Catégorie de mode", "ModeCategory", STR),
    ], "Train, bus, tram, bateau, funiculaire...",
        hierarchies=[hierarchy("Modes", ["Catégorie de mode", "Mode"])]),

    table("Statut arrivée", "cube.vw_StatutMesure", [
        col("StatusKey", "StatusKey", INT, hidden=True),
        col("Statut arrivée", "StatusLabel", STR),
        col("Arrivée mesurée", "IsMeasured", BOOL),
    ], "Qualité de l'heure d'arrivée réelle (mesurée, estimée, prévision...)."),

    table("Statut départ", "cube.vw_StatutMesure", [
        col("StatusKey", "StatusKey", INT, hidden=True),
        col("Statut départ", "StatusLabel", STR),
        col("Départ mesuré", "IsMeasured", BOOL),
    ], "Qualité de l'heure de départ réelle (même référentiel que l'arrivée)."),

    table("Passages", "cube.vw_Passage", [
        col("DateKey", "DateKey", INT, hidden=True),
        col("TimeKey", "TimeKey", INT, hidden=True),
        col("HourKey", "HourKey", INT, hidden=True),
        col("StationKey", "StationKey", INT, hidden=True),
        col("CantonKey", "CantonKey", INT, hidden=True),
        col("OperatorKey", "OperatorKey", INT, hidden=True),
        col("LineKey", "LineKey", INT, hidden=True),
        col("TransportModeKey", "TransportModeKey", INT, hidden=True),
        col("ArrivalStatusKey", "ArrivalStatusKey", INT, hidden=True),
        col("DepartureStatusKey", "DepartureStatusKey", INT, hidden=True),
        col("Trajet", "TripId", STR, hidden=True),
        col("Retard (min)", "DelayMinutes", DEC, hidden=True),
        col("Retard positif (min)", "PositiveDelayMinutes", DEC, hidden=True),
        col("Trajet supplémentaire", "IsAdditionalTrip", BOOL),
        col("Passage sans arrêt", "IsPassThrough", BOOL),
        col("StopCount", "StopCount", INT, hidden=True),
        col("CancelledCount", "CancelledCount", INT, hidden=True),
        col("MeasuredCount", "MeasuredCount", INT, hidden=True),
        col("PunctualCount", "PunctualCount", INT, hidden=True),
    ], "FAIT : un passage d'un trajet à un arrêt (horaire prévu vs réel).", measures=[
        measure("Nb passages", "SUM ( 'Passages'[StopCount] )", "#,0", "1. Volumes",
                "Nombre de passages planifiés (un trajet qui dessert un arrêt)."),
        measure("Nb trajets",
                "SUMX ( VALUES ( 'Date'[DateKey] ), CALCULATE ( DISTINCTCOUNT ( 'Passages'[Trajet] ) ) )",
                "#,0", "1. Volumes",
                "Nombre de trajets distincts (un identifiant de trajet se répète chaque jour, d'où le calcul jour par jour)."),
        measure("Nb passages mesurés", "SUM ( 'Passages'[MeasuredCount] )", "#,0", "1. Volumes",
                "Passages dont l'heure réelle est mesurée ou estimée (base des indicateurs de ponctualité)."),
        measure("Nb passages ponctuels", "SUM ( 'Passages'[PunctualCount] )", "#,0", "2. Ponctualité",
                "Passages mesurés avec moins de 3 minutes de retard (définition CFF)."),
        measure("Taux de ponctualité",
                "DIVIDE ( [Nb passages ponctuels], [Nb passages mesurés] )", "0.0 %", "2. Ponctualité",
                "Part des passages mesurés arrivés avec moins de 3 minutes de retard."),
        measure("Taux de ponctualité J-7",
                "CALCULATE ( [Taux de ponctualité], DATEADD ( 'Date'[Date], -7, DAY ) )", "0.0 %",
                "2. Ponctualité", "Même indicateur une semaine plus tôt."),
        measure("Évolution ponctualité vs J-7",
                "IF ( NOT ISBLANK ( [Taux de ponctualité J-7] ), [Taux de ponctualité] - [Taux de ponctualité J-7] )",
                "+0.0 %;-0.0 %;0.0 %", "2. Ponctualité", "Écart (en points) avec la semaine précédente."),
        measure("Retard moyen (min)", "AVERAGE ( 'Passages'[Retard (min)] )", "0.00", "3. Retards",
                "Retard moyen des passages mesurés (une avance compte en négatif)."),
        measure("Retard max (min)", "MAX ( 'Passages'[Retard (min)] )", "0.0", "3. Retards",
                "Plus gros retard mesuré."),
        measure("Retard cumulé (h)", "SUM ( 'Passages'[Retard positif (min)] ) / 60", "#,0.0", "3. Retards",
                "Somme des retards (avances ignorées), en heures."),
        measure("Nb passages retard ≥ 5 min",
                "CALCULATE ( [Nb passages mesurés], 'Passages'[Retard (min)] >= 5 )", "#,0", "3. Retards",
                "Passages mesurés avec au moins 5 minutes de retard."),
        measure("Nb suppressions", "SUM ( 'Passages'[CancelledCount] )", "#,0", "4. Suppressions",
                "Passages supprimés (trajet annulé)."),
        measure("Taux de suppression", "DIVIDE ( [Nb suppressions], [Nb passages] )", "0.00 %",
                "4. Suppressions", "Part des passages planifiés qui ont été supprimés."),
        measure("Taux de ponctualité - heures pluvieuses",
                "VAR HeuresPluie =\n"
                "    CALCULATETABLE (\n"
                "        SUMMARIZE ( 'Météo', 'Météo'[DateKey], 'Météo'[TimeKey], 'Météo'[CantonKey] ),\n"
                "        'Météo'[IsWetHour] = 1\n"
                "    )\n"
                "RETURN\n"
                "    CALCULATE (\n"
                "        [Taux de ponctualité],\n"
                "        TREATAS ( HeuresPluie, 'Passages'[DateKey], 'Passages'[HourKey], 'Passages'[CantonKey] )\n"
                "    )",
                "0.0 %", "5. Météo croisée",
                "Ponctualité des passages ayant eu lieu pendant une heure de pluie/neige dans leur canton."),
        measure("Taux de ponctualité - heures sèches",
                "VAR HeuresSeches =\n"
                "    CALCULATETABLE (\n"
                "        SUMMARIZE ( 'Météo', 'Météo'[DateKey], 'Météo'[TimeKey], 'Météo'[CantonKey] ),\n"
                "        'Météo'[IsWetHour] = 0\n"
                "    )\n"
                "RETURN\n"
                "    CALCULATE (\n"
                "        [Taux de ponctualité],\n"
                "        TREATAS ( HeuresSeches, 'Passages'[DateKey], 'Passages'[HourKey], 'Passages'[CantonKey] )\n"
                "    )",
                "0.0 %", "5. Météo croisée",
                "Ponctualité des passages ayant eu lieu pendant une heure sans précipitations dans leur canton."),
    ]),

    table("Météo", "cube.vw_Meteo", [
        col("DateKey", "DateKey", INT, hidden=True),
        col("TimeKey", "TimeKey", INT, hidden=True),
        col("CantonKey", "CantonKey", INT, hidden=True),
        col("Temperature", "Temperature", DEC, hidden=True),
        col("Precipitation", "Precipitation", DEC, hidden=True),
        col("Snowfall", "Snowfall", DEC, hidden=True),
        col("WindSpeed", "WindSpeed", DEC, hidden=True),
        col("IsWetHour", "IsWetHour", INT, hidden=True),
    ], "FAIT : météo horaire au chef-lieu de chaque canton (Open-Meteo).", measures=[
        measure("Température moyenne (°C)", "AVERAGE ( 'Météo'[Temperature] )", "0.0", "Météo",
                "Température moyenne à 2 m."),
        measure("Précipitations (mm)", "SUM ( 'Météo'[Precipitation] )", "#,0.0", "Météo",
                "Cumul de pluie (additionné sur les heures et cantons sélectionnés)."),
        measure("Neige (cm)", "SUM ( 'Météo'[Snowfall] )", "#,0.0", "Météo", "Cumul de neige fraîche."),
        measure("Vent moyen (km/h)", "AVERAGE ( 'Météo'[WindSpeed] )", "0.0", "Météo", "Vitesse moyenne du vent à 10 m."),
        measure("Heures pluvieuses", "SUM ( 'Météo'[IsWetHour] )", "#,0", "Météo",
                "Nombre d'heures x cantons avec au moins 0,5 mm de pluie ou de la neige."),
    ]),
]


def rel(from_table, from_col, to_table, to_col):
    return {"name": f"{from_table}_{from_col}_{to_table}", "fromTable": from_table, "fromColumn": from_col,
            "toTable": to_table, "toColumn": to_col}


relationships = [
    rel("Passages", "DateKey", "Date", "DateKey"),
    rel("Passages", "TimeKey", "Heure", "TimeKey"),
    rel("Passages", "StationKey", "Gare", "StationKey"),
    rel("Passages", "CantonKey", "Canton", "CantonKey"),
    rel("Passages", "OperatorKey", "Opérateur", "OperatorKey"),
    rel("Passages", "LineKey", "Ligne", "LineKey"),
    rel("Passages", "TransportModeKey", "Mode de transport", "TransportModeKey"),
    rel("Passages", "ArrivalStatusKey", "Statut arrivée", "StatusKey"),
    rel("Passages", "DepartureStatusKey", "Statut départ", "StatusKey"),
    rel("Météo", "DateKey", "Date", "DateKey"),
    rel("Météo", "TimeKey", "Heure", "TimeKey"),
    rel("Météo", "CantonKey", "Canton", "CantonKey"),
]

model = {
    "name": "SemanticModel",
    "compatibilityLevel": 1600,
    "model": {
        "culture": "fr-FR",
        "description": "DWH Suisse : ponctualité des transports publics suisses croisée avec la météo.",
        "dataSources": [{
            "name": DS,
            "connectionString": "Provider=MSOLEDBSQL.1;Data Source=localhost;Initial Catalog=CH_DWH;"
                                "Integrated Security=SSPI;Persist Security Info=False",
            "impersonationMode": "impersonateServiceAccount",
        }],
        "tables": tables,
        "relationships": relationships,
        "roles": [
            {"name": "Lecteurs", "modelPermission": "read",
             "description": "Lecture de tout le modèle. Ajouter ici les comptes Windows autorisés."},
            {"name": "Lecteurs Suisse romande", "modelPermission": "read",
             "description": "Exemple de sécurité au niveau des lignes (RLS) : ne voit que les cantons romands.",
             "tablePermissions": [{"name": "Canton",
                                   "filterExpression": "'Canton'[Région linguistique] = \"Suisse romande\""}]},
        ],
        "annotations": [{"name": "ClientCompatibilityLevel", "value": "700"}],
    },
    "id": "SemanticModel",
}

SMPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Development</Configuration>
    <SchemaVersion>2.0</SchemaVersion>
    <ProjectGuid>{8B1C6E52-1F0B-4C77-9C3B-5D2B7F3A9E11}</ProjectGuid>
    <OutputType>Exe</OutputType>
    <RootNamespace>MyRootNamespace</RootNamespace>
    <AssemblyName>MyAssemblyName</AssemblyName>
    <Name>DWH_Suisse_Cube</Name>
    <DeploymentServerName>localhost</DeploymentServerName>
    <DeploymentServerDatabase>DWH_Suisse_Cube</DeploymentServerDatabase>
    <DeploymentServerCubeName>Model</DeploymentServerCubeName>
    <DeploymentServerEdition>Developer</DeploymentServerEdition>
    <OutputDirectory>bin\\</OutputDirectory>
    <ProcessingOption>Default</ProcessingOption>
    <TransactionalDeployment>False</TransactionalDeployment>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)' == 'Development' ">
    <OutputPath>bin\\</OutputPath>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Model.bim">
      <SubType>Code</SubType>
    </Compile>
  </ItemGroup>
  <Import Project="$(MSBuildExtensionsPath)\\Business Intelligence Semantic Model\\1.0\\Microsoft.AnalysisServices.VSHostBuilder.targets" />
</Project>
"""


def main():
    os.makedirs(ROOT, exist_ok=True)
    with open(os.path.join(ROOT, "Model.bim"), "w", encoding="utf-8", newline="\r\n") as f:
        json.dump(model, f, ensure_ascii=False, indent=2)
    with open(os.path.join(ROOT, "DWH_Suisse_Cube.smproj"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(SMPROJ)
    n_measures = sum(len(t.get("measures", [])) for t in tables)
    print(f"Model.bim : {len(tables)} tables, {len(relationships)} relations, {n_measures} mesures")


if __name__ == "__main__":
    main()
