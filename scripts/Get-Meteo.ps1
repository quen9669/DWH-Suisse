<#
.SYNOPSIS
    Télécharge la météo horaire (Open-Meteo, gratuit, sans clé) pour le
    chef-lieu de chacun des 26 cantons, pour les jours des fichiers Istdaten.

.DESCRIPTION
    - Les jours traités sont déduits des fichiers présents dans  istdaten\
      (donc : lancer Get-Istdaten.ps1 AVANT ce script).
    - 1 fichier JSON brut par canton et par jour :  meteo\meteo_ZH_2026-10-25.json
    - Le JSON est enregistré en UTF-16 pour que SQL Server puisse le lire
      directement (OPENROWSET ... SINGLE_NCLOB).
    - Les fichiers déjà présents ou archivés ne sont pas re-téléchargés.

.PARAMETER DataFolder
    Dossier racine des données (défaut : C:\DWH_Suisse\data)

.PARAMETER Dates
    (optionnel) Liste de dates au format AAAA-MM-JJ, pour forcer les jours.
#>
param(
    [string]   $DataFolder = 'C:\DWH_Suisse\data',
    [string[]] $Dates
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"
Initialize-Log -DataFolder $DataFolder -ScriptName 'Get-Meteo'

try {
    $target  = Join-Path $DataFolder 'meteo'
    $archive = Join-Path $DataFolder 'archive\meteo'
    New-Item -ItemType Directory -Force -Path $target, $archive | Out-Null

    if (-not $Dates) {
        $Dates = Get-ChildItem -Path (Join-Path $DataFolder 'istdaten') -Filter '*_istdaten.csv' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name.Substring(0, 10) }
    }
    if (-not $Dates) {
        Write-Log "Aucun nouveau fichier Istdaten : pas de météo à télécharger."
        exit 0
    }

    $cantons = Import-Csv -Path (Join-Path $PSScriptRoot 'ref\cantons.csv') -Delimiter ';'
    $utf16   = New-Object System.Text.UnicodeEncoding($false, $false)   # UTF-16 LE sans BOM
    $nb = 0

    foreach ($day in $Dates) {
        foreach ($c in $cantons) {
            $name = "meteo_$($c.CantonAbbr)_$day.json"
            if ((Test-Path (Join-Path $target $name)) -or (Test-Path (Join-Path $archive $name))) { continue }

            $url = 'https://api.open-meteo.com/v1/forecast' +
                   "?latitude=$($c.Latitude)&longitude=$($c.Longitude)" +
                   "&start_date=$day&end_date=$day" +
                   '&hourly=temperature_2m,precipitation,snowfall,wind_speed_10m' +
                   '&timezone=Europe%2FZurich'

            $json = Get-WebPage -Url $url
            [System.IO.File]::WriteAllText((Join-Path $target $name), $json, $utf16)
            $nb++
            Start-Sleep -Milliseconds 200   # politesse envers l'API gratuite
        }
        Write-Log "$day : météo des 26 cantons prête."
    }

    Write-Log "Terminé : $nb fichier(s) téléchargé(s)."
    exit 0
}
catch {
    Write-Log $_.Exception.Message -Level ERREUR
    exit 1
}
