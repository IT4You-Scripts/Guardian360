[CmdletBinding()]
param (
    # === Infraestrutura do ElevaGuardian ===
    [string]$PwshPath   = 'C:\Program Files\PowerShell\7\pwsh.exe',
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',

    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # === Parâmetros repassados ao Guardian.ps1 ===
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$LogLevel,

    [switch]$Simulado,
    [string]$FileServer
)

# -------------------------------
# Função de falha controlada
# -------------------------------
function Fail {
    param ([string]$Message)
    Write-Error $Message
    exit 1
}

#region BootstrapUpgrade Guardian360 a partir do GitHub

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

# -----------------------------
# Configurações
# -----------------------------
$BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
$BasePath  = "C:\Guardian"

# Cache busting permanente (ANTI GitHub RAW cache)
$NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

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
# Execução principal (atualização)
# -----------------------------
Write-Host "Atualizando Guardian 360..." -ForegroundColor Cyan

foreach ($File in $Files) {
    try {
        Invoke-WebRequest `
            -Uri "$($File.Url)$NoCache" `
            -OutFile $File.Path `
            -UseBasicParsing `
            -ErrorAction Stop
    }
    catch {
        # falha individual ignorada (modo silencioso)
    }
}

#endregion

# -------------------------------
# Validações iniciais
# -------------------------------
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PowerShell 7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }

# Desbloqueia o script alvo silenciosamente
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# -------------------------------
# Diretório de trabalho seguro
# -------------------------------
try {
    $workDir = Split-Path -Path $ScriptPath -Parent
} catch {
    $workDir = (Get-Location).Path
}

# -------------------------------
# Construção do array de argumentos
# -------------------------------
$argList = @(
    '-ExecutionPolicy','Bypass',
    '-NoProfile',
    '-File',$ScriptPath
)

if ($NonInteractive) { $argList += '-NonInteractive' }

if ($ExecutaFases) {
    $argList += '-ExecutaFases'
    $argList += ($ExecutaFases -join ',')
}

if ($PulaFases) {
    $argList += '-PulaFases'
    $argList += ($PulaFases -join ',')
}

if ($LogLevel) {
    $argList += '-LogLevel'
    $argList += $LogLevel
}

if ($Simulado) { $argList += '-Simulado' }

if ($FileServer) {
    $argList += '-FileServer'
    $argList += $FileServer
}

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) {
    'Hidden'
} elseif ($Maximized) {
    'Maximized'
} else {
    'Normal'
}

# -------------------------------
# Execução do Guardian diretamente com array de argumentos
# -------------------------------
Write-Host "Iniciando Guardian.ps1..." -ForegroundColor Cyan

Push-Location $workDir
try {
    & $PwshPath @argList
} catch {
    Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
}
Pop-Location
