<#
.SYNOPSIS
    Télécharge le référentiel des points d'arrêt suisses (gares, arrêts de bus...).

.DESCRIPTION
    Source : https://data.opentransportdata.swiss/dataset/service-points-actual-date
    Fichier ZIP contenant un CSV (~60 000 lignes, 55 colonnes, séparateur ";").
    Le CSV est enregistré sous un nom FIXE : servicepoints\service-points.csv
    (c'est ce chemin qu'utilise le package SSIS 20_ODS_ServicePoints).

.PARAMETER DataFolder
    Dossier racine des données (défaut : C:\DWH_Suisse\data)
#>
param(
    [string] $DataFolder = 'C:\DWH_Suisse\data'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"
Initialize-Log -DataFolder $DataFolder -ScriptName 'Get-ServicePoints'

try {
    $target = Join-Path $DataFolder 'servicepoints'
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    Write-Log "Recherche du dernier fichier publié..."
    $html = Get-WebPage -Url 'https://data.opentransportdata.swiss/dataset/service-points-actual-date'
    $m = [regex]::Match($html, 'https://[^"''\s]+/download/actual-date-swiss-service-point-[\d-]+\.csv\.zip')
    if (-not $m.Success) { throw "Lien du référentiel introuvable : la page du portail a peut-être changé." }
    Write-Log "Fichier trouvé : $($m.Value.Split('/')[-1])"

    $zip   = Join-Path $target 'service-points.zip'
    $unzip = Join-Path $target 'tmp'
    Save-WebFile -Url $m.Value -Destination $zip

    if (Test-Path $unzip) { Remove-Item $unzip -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $unzip -Force
    $csv = Get-ChildItem -Path $unzip -Filter '*.csv' -Recurse | Select-Object -First 1
    if (-not $csv) { throw "Le ZIP ne contient pas de fichier CSV." }

    Move-Item -Path $csv.FullName -Destination (Join-Path $target 'service-points.csv') -Force
    Remove-Item $unzip -Recurse -Force
    Remove-Item $zip -Force

    # Contrôle de structure : le package SSIS attend exactement 55 colonnes
    $header = Get-Content (Join-Path $target 'service-points.csv') -TotalCount 1 -Encoding UTF8
    $nbCols = $header.Split(';').Count
    if ($nbCols -ne 55) {
        throw "Le fichier contient $nbCols colonnes au lieu de 55 : la source a changé de format, adapter le package SSIS."
    }

    Write-Log "Référentiel prêt : servicepoints\service-points.csv"
    exit 0
}
catch {
    Write-Log $_.Exception.Message -Level ERREUR
    exit 1
}
