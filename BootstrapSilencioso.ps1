#region BootstrapUpgrade Silencioso Guardian360 a partir do GitHub

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# Função de falha silenciosa (encerra sem exibir mensagens)
function Fail {
    param ([string]$Message)
    exit 1
}

# Configurações
$BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
$BasePath  = "C:\Guardian"
$NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

# Estrutura de pastas (cria sem exibir nada)
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

# Arquivos gerenciados
$Files = @(
    @{ Url = "$BaseUrl/Atualiza.ps1";                            Path = "$BasePath\Atualiza.ps1" },
    @{ Url = "$BaseUrl/CriaCredenciais.ps1";                     Path = "$BasePath\CriaCredenciais.ps1" },
    @{ Url = "$BaseUrl/ElevaGuardian.ps1";                       Path = "$BasePath\ElevaGuardian.ps1" },
    @{ Url = "$BaseUrl/Guardian.ps1";                            Path = "$BasePath\Guardian.ps1" },
    @{ Url = "$BaseUrl/Prepara.ps1";                             Path = "$BasePath\Prepara.ps1" },
    @{ Url = "$BaseUrl/RodaGuardian.ps1";                        Path = "$BasePath\RodaGuardian.ps1" },
    @{ Url = "$BaseUrl/Assets/Images/logotipo.png";              Path = "$BasePath\Assets\Images\logotipo.png" },
    @{ Url = "$BaseUrl/Assets/Images/guardian_bg.png";           Path = "$BasePath\Assets\Images\guardian_bg.png" },
    @{ Url = "$BaseUrl/Assets/Images/guardian_end_bg.png";       Path = "$BasePath\Assets\Images\guardian_end_bg.png" },
    @{ Url = "$BaseUrl/Functions/Block-AppUpdates.ps1";          Path = "$BasePath\Functions\Block-AppUpdates.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-AllRecycleBins.ps1";      Path = "$BasePath\Functions\Clear-AllRecycleBins.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-BrowserCache.ps1";        Path = "$BasePath\Functions\Clear-BrowserCache.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-RecentFilesHistory.ps1";  Path = "$BasePath\Functions\Clear-RecentFilesHistory.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-TempFiles.ps1";           Path = "$BasePath\Functions\Clear-TempFiles.ps1" },
    @{ Url = "$BaseUrl/Functions/Clear-WindowsUpdateCache.ps1";  Path = "$BasePath\Functions\Clear-WindowsUpdateCache.ps1" },
    @{ Url = "$BaseUrl/Functions/Confirm-MacriumBackup.ps1";     Path = "$BasePath\Functions\Confirm-MacriumBackup.ps1" },
    @{ Url = "$BaseUrl/Functions/Get-SystemInventory.ps1";       Path = "$BasePath\Functions\Get-SystemInventory.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-HDD.ps1";              Path = "$BasePath\Functions\Optimize-HDD.ps1" },
    @{ Url = "$BaseUrl/Functions/Optimize-JsonReport.ps1";       Path = "$BasePath\Functions\Optimize-JsonReport.ps1" },
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
    @{ Url = "$BaseUrl/Functions/Update-WingetApps.ps1";         Path = "$BasePath\Functions\Update-WingetApps.ps1" },
    @{ Url = "$BaseUrl/Functions/Write-JsonResult.ps1";          Path = "$BasePath\Functions\Write-JsonResult.ps1" }
)

# ------------------------------------------------------------------
# LIMPEZA SILENCIOSA
# ------------------------------------------------------------------
foreach ($File in $Files) {
    try {
        if (Test-Path $File.Path) {
            attrib -R $File.Path 2>$null
            Remove-Item $File.Path -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

# ------------------------------------------------------------------
# DOWNLOAD SILENCIOSO
# ------------------------------------------------------------------
foreach ($File in $Files) {
    try {
        Invoke-WebRequest `
            -Uri "$($File.Url)$NoCache" `
            -OutFile $File.Path `
            -UseBasicParsing `
            -Headers @{ "Cache-Control"="no-cache" } `
            -ErrorAction Stop
    }
    catch {
        # Se for imagem, ignora a falha
        if ($File.Path -match "\.png$") { continue }

        # Se for script, falha silenciosa
        Fail "Download falhou para: $($File.Path)"
    }
}

exit 0

#endregion