# ElevaGuardian.ps1
# Executa Guardian.ps1 em PowerShell 7 usando credenciais criptografadas (AES)
# Responsável por elevação, contexto de execução e repasse seguro de parâmetros

[CmdletBinding()]
param (
    # Infraestrutura
    [string]$PwshPath = (Get-Command pwsh).Source,
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',
    [string]$CredPath   = 'C:\Guardian\credenciais.xml',
    [string]$KeyPath    = 'C:\Guardian\chave.key',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Guardian.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,
    [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

# -------------------------------
# Funções auxiliares
# -------------------------------
function Show-Header {
    param([string]$Text,[ConsoleColor]$Color='Cyan')
    $bar = '─' * ($Text.Length + 2)
    Write-Host ""
    Write-Host ("┌$bar┐") -ForegroundColor $Color
    Write-Host ("│ $Text │") -ForegroundColor $Color
    Write-Host ("└$bar┘") -ForegroundColor $Color
    Write-Host ""
}

function Fail {
    param([string]$Message)
    Show-Header $Message -Color Red
    Write-Host "O script será encerrado em 5 segundos..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
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
    @{ Url = "$BaseUrl/Atualiza.ps1";                            Path = "$BasePath\Atualiza.ps1" },
    @{ Url = "$BaseUrl/CriaCredenciais.ps1";                     Path = "$BasePath\CriaCredenciais.ps1" },
    @{ Url = "$BaseUrl/ElevaGuardian.ps1";                       Path = "$BasePath\ElevaGuardian.ps1" },
    @{ Url = "$BaseUrl/Guardian.ps1";                            Path = "$BasePath\Guardian.ps1" },
    @{ Url = "$BaseUrl/Prepara.ps1";                             Path = "$BasePath\Prepara.ps1" },
    @{ Url = "$BaseUrl/Assets/Images/logotipo.png";              Path = "$BasePath\Assets\Images\logotipo.png" },
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

Show-Header "Atualizando Guardian 360..." -Color Cyan

foreach ($File in $Files) {
    try {
        Invoke-WebRequest `
            -Uri "$($File.Url)$NoCache" `
            -OutFile $File.Path `
            -UseBasicParsing `
            -ErrorAction Stop
    }
    catch {
        # falha individual ignorada
    }
}
#endregion


# -------------------------------
# Validações iniciais
# -------------------------------
try { $PwshPath   = (Resolve-Path $PwshPath).Path } catch { Fail "PowerShell 7 não encontrado em: $PwshPath" }
try { $ScriptPath = (Resolve-Path $ScriptPath).Path } catch { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }
try { $CredPath   = (Resolve-Path $CredPath).Path } catch { Fail "Credenciais não encontradas em: $CredPath" }
try { $KeyPath    = (Resolve-Path $KeyPath).Path } catch { Fail "Chave AES não encontrada em: $KeyPath" }

# -------------------------------
# Leitura das credenciais AES
# -------------------------------
try {
    [xml]$xml = Get-Content -LiteralPath $CredPath -Raw
    $user = $xml.Credenciais.UserName
    $enc  = $xml.Credenciais.EncryptedPassword
} catch { Fail "Falha ao ler credenciais: $($_.Exception.Message)" }

if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($enc)) {
    Fail "Credenciais incompletas (UserName / EncryptedPassword)."
}

try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
    $secure   = ConvertTo-SecureString -String $enc -Key $keyBytes
    if ($user -notlike '*\*' -and $user -notlike '*@*') { $user = "$env:COMPUTERNAME\$user" }
    $cred     = [System.Management.Automation.PSCredential]::new($user,$secure)
} catch { Fail "Não foi possível abrir as credenciais. Verifique chave AES." }

# =========================================================
# >>> PATCH JSON IPC (ARGUMENTOS ROBUSTOS)
# =========================================================

$argJsonPath = "C:\Guardian\guardian_arg.json"

$argsObj = @{
    FileServer    = $FileServer
    Cliente       = $Cliente
    ExecutaFases  = $ExecutaFases
    PulaFases     = $PulaFases
    LogLevel      = $LogLevel
    Simulado      = [bool]$Simulado
}

try {
    $argsObj | ConvertTo-Json -Depth 5 | Set-Content -Path $argJsonPath -Encoding UTF8
}
catch {
    Fail "Falha ao criar guardian_arg.json: $($_.Exception.Message)"
}

# =========================================================

# -------------------------------
# Montagem segura do comando
# -------------------------------
# NÃO repassar mais argumentos pela linha de comando
$argString = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
if ($NonInteractive) { $argString += " -NonInteractive" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Log do comando final
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $argString" -ForegroundColor Cyan

# -------------------------------
# Execução do Guardian
# -------------------------------
try {
    $proc = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argString `
        -Credential $cred `
        -WorkingDirectory (Split-Path $ScriptPath -Parent) `
        -WindowStyle $winStyle `
        -UseNewEnvironment `
        -PassThru

    Show-Header "Guardian iniciado com sucesso. PID: $($proc.Id)" -Color Green
}
catch {
    Fail "Falha ao iniciar Guardian.ps1: $($_.Exception.Message)"
}
