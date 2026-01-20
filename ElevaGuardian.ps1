
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

# -------------------------------
# Bootstrap: Atualização via GitHub
# -------------------------------
$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

$BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
$BasePath  = "C:\Guardian"
$NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

$Folders = @("$BasePath","$BasePath\Functions","$BasePath\Assets\Images")
foreach ($Folder in $Folders) {
    if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
}

Show-Header "Atualizando Guardian 360..." -Color Cyan
# (Bloco de atualização comentado para evitar download automático)
foreach ($File in $Files) { try { Invoke-WebRequest -Uri "$($File.Url)$NoCache" -OutFile $File.Path -UseBasicParsing } catch {} }

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

# -------------------------------
# Montagem segura do comando
# -------------------------------
$argString = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
if ($NonInteractive) { $argString += " -NonInteractive" }
if ($ExecutaFases)   { $argString += " -ExecutaFases $($ExecutaFases -join ',')" }
if ($PulaFases)      { $argString += " -PulaFases $($PulaFases -join ',')" }
if ($LogLevel)       { $argString += " -LogLevel $LogLevel" }
if ($Simulado)       { $argString += " -Simulado" }
if ($FileServer)     { $argString += " -FileServer $FileServer" }
if ($Cliente)        { $argString += " -Cliente `"$Cliente`"" }

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
} catch {
    Fail "Falha ao iniciar Guardian.ps1: $($_.Exception.Message)"
}
