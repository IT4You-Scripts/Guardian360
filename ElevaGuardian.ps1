
# ElevaGuardian.ps1
# Executa Guardian.ps1 em PowerShell 7 usando credenciais criptografadas (agora via DPAPI, sem key.bin)
# Responsável apenas por elevação, contexto de execução e repasse de parâmetros

[CmdletBinding()]
param (
    # === Infraestrutura do ElevaGuardian ===
    [string]$PwshPath = (Get-Command pwsh).Source,
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',
    [string]$CredPath   = 'C:\Guardian\credenciais.xml',
    #[string]$KeyPath    = 'C:\Guardian\key.bin',  # Mantido para compatibilidade, mas não será usado

    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # === Parâmetros repassados ao Guardian.ps1 ===
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$LogLevel,

    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

# -------------------------------
# Função para cabeçalho estilizado
# -------------------------------
function Show-Header {
    param(
        [string]$Text,
        [ConsoleColor]$Color = 'Cyan'
    )

    $bar = '─' * ($Text.Length + 2)
    Write-Host ""
    Write-Host ("┌$bar┐") -ForegroundColor $Color
    Write-Host ("│ $Text │") -ForegroundColor $Color
    Write-Host ("└$bar┘") -ForegroundColor $Color
    Write-Host ""
}

# -------------------------------
# Função de falha controlada
# -------------------------------
function Fail {
    param ([string]$Message)
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
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PowerShell 7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }
if (-not (Test-Path -LiteralPath $CredPath))   { Fail "Credenciais não encontradas em: $CredPath. Gere o arquivo antes de continuar." }

# Desbloqueia o script alvo silenciosamente
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# -------------------------------
# *** ATUALIZAÇÃO: Criptografia DPAPI ***
# -------------------------------
# Antes: Leitura da chave AES (key.bin) e uso do -Key
# Agora: DPAPI (ConvertTo-SecureString sem chave)
# Mantemos comentários e estrutura, mas ignoramos key.bin

# Leitura das credenciais
$user = $null
$enc  = $null

try {
    $raw = Get-Content -LiteralPath $CredPath -Raw -ErrorAction Stop
} catch {
    Fail "Falha ao ler o arquivo de credenciais: $($_.Exception.Message)"
}

if ($raw -match '<\s*Credenciais\b') {
    try {
        [xml]$xml = $raw
        $user = $xml.Credenciais.UserName
        $enc  = $xml.Credenciais.EncryptedPassword
    } catch {
        Fail "XML de credenciais inválido: $($_.Exception.Message)"
    }
} else {
    try {
        $data = Import-Clixml -Path $CredPath -ErrorAction Stop
        $user = $data.UserName
        $enc  = $data.EncryptedPassword
    } catch {
        Fail "Arquivo de credenciais não é XML manual nem Clixml válido."
    }
}

if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($enc)) {
    Fail "Credenciais incompletas (UserName / EncryptedPassword)."
}

# Reconstrução do PSCredential usando DPAPI
try {
    # Antes: $secure = ConvertTo-SecureString -String $enc -Key $keyBytes
    # Agora: DPAPI (sem chave)
    $secure = ConvertTo-SecureString -String $enc
} catch {
    Fail "Falha ao descriptografar a senha via DPAPI."
}

if ($user -notlike '*\*' -and $user -notlike '*@*') {
    $user = "$env:COMPUTERNAME\$user"
}

try {
    $cred = [System.Management.Automation.PSCredential]::new($user, $secure)
} catch {
    Fail "Falha ao criar PSCredential: $($_.Exception.Message)"
}

# -------------------------------
# Construção segura do ArgumentList
# -------------------------------
$argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File', $ScriptPath)
if ($NonInteractive) { $argList += '-NonInteractive' }
if ($ExecutaFases)   { $argList += '-ExecutaFases'; $argList += ($ExecutaFases -join ',') }
if ($PulaFases)      { $argList += '-PulaFases'; $argList += ($PulaFases -join ',') }
if ($LogLevel)       { $argList += '-LogLevel'; $argList += $LogLevel }
if ($Simulado)       { $argList += '-Simulado' }
if ($FileServer)     { $argList += '-FileServer'; $argList += $FileServer }
if ($Cliente)        { $argList += '-Cliente'; $argList += "`"$Cliente`"" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Diretório de trabalho seguro
# -------------------------------
try { $workDir = Split-Path -Path $ScriptPath -Parent } catch { $workDir = (Get-Location).Path }

# -------------------------------
# Execução do Guardian
# -------------------------------
try {
    $proc = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argList `
        -Credential $cred `
        -WorkingDirectory $workDir `
        -WindowStyle $winStyle `
        -UseNewEnvironment `
        -PassThru

    Show-Header "Guardian iniciado com sucesso. PID: $($proc.Id)" -Color Green
}
catch {
    if ($_.Exception.Message -like "*Nome de usuário ou senha incorretos*") {
        Fail "Credenciais incorretas. Verifique usuário e senha e tente novamente."
    } else {
        Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
    }
}
