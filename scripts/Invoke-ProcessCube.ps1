<#
.SYNOPSIS
    "Traite" (recharge) le cube SSAS Tabular depuis l'entrepôt CH_DWH.

.DESCRIPTION
    Envoie une commande TMSL "refresh full" au serveur Analysis Services.
    Nécessite le module PowerShell SqlServer (installé par Initialize-Environment.ps1).
    Appelé par le package SSIS 50_SSAS_Traitement.dtsx.

.PARAMETER Server
    Serveur Analysis Services (défaut : localhost)

.PARAMETER Database
    Nom du modèle déployé (défaut : DWH_Suisse_Cube)
#>
param(
    [string] $Server     = 'localhost',
    [string] $Database   = 'DWH_Suisse_Cube',
    [string] $DataFolder = 'C:\DWH_Suisse\data'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"
Initialize-Log -DataFolder $DataFolder -ScriptName 'Invoke-ProcessCube'

try {
    Import-Module SqlServer -DisableNameChecking

    $tmsl = @{
        refresh = @{
            type    = 'full'
            objects = @(@{ database = $Database })
        }
    } | ConvertTo-Json -Depth 5

    Write-Log "Traitement du modèle '$Database' sur '$Server'..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-ASCmd -Server $Server -Query $tmsl

    # Invoke-ASCmd ne lève pas d'exception sur une erreur métier : on lit la réponse XML
    if ($result -match '<Error ') {
        $msg = ([regex]::Matches($result, 'Description="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) -join ' | '
        throw "Échec du traitement du cube : $msg"
    }

    Write-Log "Cube traité en $([int]$sw.Elapsed.TotalSeconds) s."
    exit 0
}
catch {
    Write-Log $_.Exception.Message -Level ERREUR
    exit 1
}
