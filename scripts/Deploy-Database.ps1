<#
.SYNOPSIS
    Crée (ou met à jour) les 4 bases du projet en exécutant les scripts
    sql\01 à sql\09 dans l'ordre.

.DESCRIPTION
    Les scripts sont ré-exécutables : relancer ce déploiement ne supprime
    aucune donnée (les tables existantes sont conservées, les procédures et
    vues sont mises à jour).
    Alternative manuelle : ouvrir chaque fichier .sql dans SSMS et appuyer sur F5.

.PARAMETER ServerInstance
    Instance SQL Server (défaut : localhost ; ex. "localhost\SQLEXPRESS" pour une instance nommée)

.EXAMPLE
    .\Deploy-Database.ps1
    .\Deploy-Database.ps1 -ServerInstance "MONPC\DEV"
#>
param(
    [string] $ServerInstance = 'localhost'
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer -DisableNameChecking

$sqlFolder = Join-Path (Split-Path $PSScriptRoot -Parent) 'sql'
$scripts = Get-ChildItem -Path $sqlFolder -Filter '0*.sql' | Sort-Object Name

# Les versions récentes du module chiffrent la connexion par défaut :
# en local, on fait confiance au certificat auto-signé du serveur.
$extra = @{}
if ((Get-Command Invoke-Sqlcmd).Parameters.ContainsKey('TrustServerCertificate')) {
    $extra['TrustServerCertificate'] = $true
}

foreach ($s in $scripts) {
    Write-Host ">>> $($s.Name)" -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $ServerInstance -InputFile $s.FullName `
                  -QueryTimeout 1800 -Verbose -AbortOnError @extra 4>&1 |
        ForEach-Object { Write-Host "    $_" }
}

Write-Host "`nBases CH_ADMIN, CH_ODS, CH_STG, CH_DWH prêtes sur $ServerInstance." -ForegroundColor Green
Write-Host "Étape suivante : ouvrir ssis\DWH_Suisse_ETL\DWH_Suisse_ETL.dtproj dans Visual Studio." -ForegroundColor Green
