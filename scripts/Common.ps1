<#
    Fonctions communes aux scripts du projet DWH Suisse.
    Chargé par les autres scripts avec :  . "$PSScriptRoot\Common.ps1"
#>

# Accélère fortement Invoke-WebRequest (pas de barre de progression)
$ProgressPreference = 'SilentlyContinue'
# Les sites open data exigent TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    <# Écrit un message à l'écran ET dans data\logs\<script>_<date>.log #>
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERREUR')] [string] $Level = 'INFO'
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Output $line
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 }
}

function Initialize-Log {
    param([Parameter(Mandatory)] [string] $DataFolder, [Parameter(Mandatory)] [string] $ScriptName)
    $logDir = Join-Path $DataFolder 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogFile = Join-Path $logDir ('{0}_{1:yyyy-MM-dd}.log' -f $ScriptName, (Get-Date))
}

function Get-WebPage {
    <# Télécharge une page web en texte (UTF-8) #>
    param([Parameter(Mandatory)] [string] $Url)
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add('User-Agent', 'DWH-Suisse-Formation/1.0 (projet personnel)')
    try { return $wc.DownloadString($Url) } finally { $wc.Dispose() }
}

function Save-WebFile {
    <#
        Télécharge un fichier dans un ".part" puis le renomme une fois complet :
        SSIS ne verra jamais un fichier à moitié téléchargé.
    #>
    param([Parameter(Mandatory)] [string] $Url, [Parameter(Mandatory)] [string] $Destination)
    $part = "$Destination.part"
    if (Test-Path $part) { Remove-Item $part -Force }
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'DWH-Suisse-Formation/1.0 (projet personnel)')
    try { $wc.DownloadFile($Url, $part) } finally { $wc.Dispose() }
    Move-Item -Path $part -Destination $Destination -Force
}
