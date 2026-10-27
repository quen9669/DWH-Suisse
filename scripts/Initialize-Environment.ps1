<#
.SYNOPSIS
    Prépare le PC pour le projet (à lancer UNE fois, après l'installation des logiciels).

.DESCRIPTION
    1. Vérifie la présence des services SQL Server / SSAS / SQL Agent
    2. Crée l'arborescence des données (C:\DWH_Suisse\data\...)
    3. Donne aux comptes de service SQL Server le droit d'accéder à ce dossier
       (SQL Server lit les fichiers météo ; SQL Agent exécute les téléchargements)
    4. Installe le module PowerShell "SqlServer" (pour le déploiement et le cube)

.EXAMPLE
    Clic droit sur PowerShell > "Exécuter en tant qu'administrateur", puis :
    cd C:\DWH_Suisse\DWH-Suisse\scripts
    .\Initialize-Environment.ps1
#>
param(
    [string] $DataFolder = 'C:\DWH_Suisse\data'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== 1. Services installés ===" -ForegroundColor Cyan
$expected = @(
    @{ Name = 'MSSQLSERVER';     Role = 'Moteur SQL Server (bases de données)' },
    @{ Name = 'SQLSERVERAGENT';  Role = 'SQL Server Agent (planification) - optionnel au début' },
    @{ Name = 'MSSQLServerOLAPService'; Role = 'Analysis Services (cube)' },
    @{ Name = 'MsDtsServer160';  Role = 'Integration Services 2022 (optionnel)' }
)
foreach ($s in $expected) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($svc) { Write-Host ("  [OK]      {0,-24} {1} - {2}" -f $s.Name, $svc.Status, $s.Role) -ForegroundColor Green }
    else      { Write-Host ("  [ABSENT]  {0,-24} {1}" -f $s.Name, $s.Role) -ForegroundColor Yellow }
}

Write-Host "`n=== 2. Dossiers de données ===" -ForegroundColor Cyan
$folders = 'istdaten', 'servicepoints', 'meteo', 'archive\istdaten', 'archive\meteo', 'logs'
foreach ($f in $folders) {
    $p = Join-Path $DataFolder $f
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Write-Host "  $p"
}

Write-Host "`n=== 3. Droits des comptes de service sur $DataFolder ===" -ForegroundColor Cyan
foreach ($account in 'NT SERVICE\MSSQLSERVER', 'NT SERVICE\SQLSERVERAGENT') {
    $svcName = $account.Split('\')[1]
    if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
        & icacls $DataFolder /grant "${account}:(OI)(CI)M" /T /Q | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  [OK] $account : modification autorisée" -ForegroundColor Green }
        else { Write-Host "  [KO] $account : relancez ce script en administrateur" -ForegroundColor Red }
    }
}

Write-Host "`n=== 4. Module PowerShell SqlServer ===" -ForegroundColor Cyan
if (Get-Module -ListAvailable -Name SqlServer) {
    Write-Host "  [OK] déjà installé" -ForegroundColor Green
}
else {
    Write-Host "  Installation (quelques minutes)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    Install-Module -Name SqlServer -Scope CurrentUser -AllowClobber -Force
    Write-Host "  [OK] installé" -ForegroundColor Green
}

Write-Host "`nEnvironnement prêt. Étape suivante : .\Deploy-Database.ps1" -ForegroundColor Cyan
