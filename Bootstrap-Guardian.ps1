#Requires -Version 7.0

# =========================================
# Guardian360 - Bootstrap / Update Seguro
# =========================================

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# -----------------------------
# Configurações
# -----------------------------
$BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
$BasePath  = "C:\Guardian"

# Cache busting permanente (ANTI GitHub RAW cache)
$NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

$RemoteVersionUrl = "$BaseUrl/version.json$NoCache"
$LocalVersionFile = "$BasePath\version.json"

# -----------------------------
# Estrutura base (NUNCA apaga)
# -----------------------------
$Folders = @(
    $BasePath,
    "$BasePath\Functions",
    "$BasePath\Assets\Images"
)

foreach ($Folder in $Folders) {
    if (-not (Test-Path $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }
}

# -----------------------------
# Arquivos gerenciados
# -----------------------------
$Files = @(
    @{ Url = "$BaseUrl/Guardian.ps1";        Path = "$BasePath\Guardian.ps1" },
    @{ Url = "$BaseUrl/ElevaGuardian.ps1";   Path = "$BasePath\ElevaGuardian.ps1" },
    @{ Url = "$BaseUrl/Assets/Images/logotipo.png"; Path = "$BasePath\Assets\Images\logotipo.png" },
    @{ Url = "$BaseUrl/Functions/Block-AppUpdates.ps1";          Path = "$BasePath\Functions\Block-AppUpdates.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-AllRecycleBins.ps1";      Path = "$BasePath\Functions\Clear-AllRecycleBins.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-BrowserCache.ps1";        Path = "$BasePath\Functions\Clear-BrowserCache.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-RecentFilesHistory.ps1";  Path = "$BasePath\Functions\Clear-RecentFilesHistory.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-TempFiles.ps1";           Path = "$BasePath\Functions\Clear-TempFiles.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-WindowsUpdateCache.ps1";  Path = "$BasePath\Functions\Clear-WindowsUpdateCache.ps1" },
    @{ Url = "$BaseUrl/Functions/Confirm-MacriumBackup.ps1";     Path = "$BasePath\Functions\Confirm-MacriumBackup.ps1" },
    @{ Url = "$BaseUrl/Functions/Get-SystemInventory.ps1";       Path = "$BasePath\Functions\Get-SystemInventory.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-HDD.ps1";              Path = "$BasePath\Functions\Optimize-HDD.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-NetworkSettings.ps1";  Path = "$BasePath\Functions\Optimize-NetworkSettings.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-PowerSettings.ps1";    Path = "$BasePath\Functions\Optimize-PowerSettings.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-SSD.ps1";              Path = "$BasePath\Functions\Optimize-SSD.ps1" },
    @{ Url = "$BaseUrl/Functions/Remove-OldUpdateFiles.ps1";     Path = "$BasePath\Functions\Remove-OldUpdateFiles.ps1" },
    @{ Url = "$BaseUrl/Functions/Repair-SystemIntegrity.ps1";    Path = "$BasePath\Functions\Repair-SystemIntegrity.ps1" },
    @{ Url = "$BaseUrl/Functions/Scan-AntiMalware.ps1";          Path = "$BasePath\Functions\Scan-AntiMalware.ps1" },
    @{ Url = "$BaseUrl/Functions/Send-LogToServer.ps1";          Path = "$BasePath\Functions\Send-LogToServer.ps1" },
    @{ Url = "$BaseUrl/Functions/Show-GuardianEndUI.ps1";        Path = "$BasePath\Functions\Show-GuardianEndUI.ps1" },
    @{ Url = "$BaseUrl/Functions/Show-GuardianUI.ps1";           Path = "$BasePath\Functions\Show-GuardianUI.ps1" },
    @{ Url = "$BaseUrl/Functions/Update-MicrosoftStore.ps1";     Path = "$BasePath\Functions\Update-MicrosoftStore.ps1" },
    @{ Url = "$BaseUrl/Functions/Update-WindowsOS.ps1";          Path = "$BasePath\Functions\Update-WindowsOS.ps1" },
    @{ Url = "$BaseUrl/Functions/Update-WingetApps.ps1";         Path = "$BasePath\Functions\Update-WingetApps.ps1" }
)

# -----------------------------
# Funções auxiliares
# -----------------------------
function Get-RemoteVersion {
    Invoke-RestMethod -Uri $RemoteVersionUrl -UseBasicParsing
}

function Get-LocalVersion {
    if (Test-Path $LocalVersionFile) {
        Get-Content $LocalVersionFile -Raw | ConvertFrom-Json
    } else {
        $null
    }
}

function Needs-Update {
    param ($Local, $Remote)

    if (-not $Local) { return $true }

    try {
        [version]$Remote.version -gt [version]$Local.version
    }
    catch {
        $true
    }
}

# -----------------------------
# Execução principal
# -----------------------------
try {
    $RemoteVersion = Get-RemoteVersion
    $LocalVersion  = Get-LocalVersion

    if (Needs-Update $LocalVersion $RemoteVersion) {

        $from = if ($LocalVersion) { $LocalVersion.version } else { "ainda não instalado" }
        $to   = $RemoteVersion.version

        Write-Host "Atualizando o programa Guardian 360 ($from → $to)..." -ForegroundColor Cyan

        foreach ($File in $Files) {
            try {
                Invoke-WebRequest `
                    -Uri $File.Url `
                    -OutFile $File.Path `
                    -UseBasicParsing `
                    -ErrorAction Stop
            }
            catch {
                # falha individual ignorada (modo silencioso)
            }
        }

        # Grava versão remota como versão local
        $RemoteVersion | ConvertTo-Json -Depth 5 |
            Set-Content $LocalVersionFile -Encoding UTF8
    }

    exit 0
}
catch {
    exit 1
}
