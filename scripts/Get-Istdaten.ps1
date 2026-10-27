<#
.SYNOPSIS
    Télécharge les fichiers "Ist-Daten" (passages réels des transports publics
    suisses) des N derniers jours disponibles.

.DESCRIPTION
    Source : https://data.opentransportdata.swiss/dataset/ist-daten-v2
    - 1 fichier CSV par jour (~300 à 500 Mo, 2 à 3 millions de lignes)
    - le portail ne conserve qu'environ 50 jours en ligne
    Un fichier déjà présent dans  istdaten\  ou déjà archivé dans
    archive\istdaten\  n'est pas re-téléchargé (chargement incrémental).

.PARAMETER DataFolder
    Dossier racine des données (défaut : C:\DWH_Suisse\data)

.PARAMETER NbJours
    Nombre de jours les plus récents à récupérer (défaut : 3).
    Attention à l'espace disque : ~0,5 Go par jour en CSV.

.EXAMPLE
    .\Get-Istdaten.ps1 -NbJours 7
#>
param(
    [string] $DataFolder = 'C:\DWH_Suisse\data',
    [ValidateRange(1, 60)] [int] $NbJours = 3
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"
Initialize-Log -DataFolder $DataFolder -ScriptName 'Get-Istdaten'

try {
    $target  = Join-Path $DataFolder 'istdaten'
    $archive = Join-Path $DataFolder 'archive\istdaten'
    New-Item -ItemType Directory -Force -Path $target, $archive | Out-Null

    Write-Log "Lecture de la liste des fichiers disponibles..."
    $html = Get-WebPage -Url 'https://data.opentransportdata.swiss/dataset/ist-daten-v2'

    $files = [regex]::Matches($html, 'https://[^"''\s]+/download/(\d{4}-\d{2}-\d{2})_istdaten\.csv') |
        ForEach-Object { [pscustomobject]@{ Url = $_.Value; Day = $_.Groups[1].Value } } |
        Sort-Object Day -Unique |
        Select-Object -Last $NbJours

    if (-not $files) { throw "Aucun lien de fichier Istdaten trouvé : la page du portail a peut-être changé." }

    Write-Log ("Jours retenus : {0}" -f (($files | ForEach-Object Day) -join ', '))

    foreach ($f in $files) {
        $name = "$($f.Day)_istdaten.csv"
        if ((Test-Path (Join-Path $target $name)) -or (Test-Path (Join-Path $archive $name))) {
            Write-Log "$name : déjà présent, ignoré."
            continue
        }
        Write-Log "$name : téléchargement en cours (plusieurs minutes possibles)..."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Save-WebFile -Url $f.Url -Destination (Join-Path $target $name)
        $sizeMb = [math]::Round((Get-Item (Join-Path $target $name)).Length / 1MB, 1)
        Write-Log "$name : OK ($sizeMb Mo en $([int]$sw.Elapsed.TotalSeconds) s)"
    }

    Write-Log "Terminé."
    exit 0
}
catch {
    Write-Log $_.Exception.Message -Level ERREUR
    exit 1
}
