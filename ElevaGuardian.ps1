# ElevaGuardian.ps1
# Executa Guardian.ps1 em PowerShell 7 usando credenciais criptografadas (key.bin + credenciais.xml)
# Responsável apenas por elevação, contexto de execução e repasse de parâmetros

[CmdletBinding()]
param (
    # === Infraestrutura do ElevaGuardian ===
    [string]$PwshPath   = 'C:\Program Files\PowerShell\7\pwsh.exe',
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',
    [string]$CredPath   = 'C:\Guardian\credenciais.xml',
    [string]$KeyPath    = 'C:\Guardian\key.bin',

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

# -------------------------------
# Validações iniciais
# -------------------------------
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PowerShell 7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }
if (-not (Test-Path -LiteralPath $CredPath))   { Fail "Credenciais não encontradas em: $CredPath" }
if (-not (Test-Path -LiteralPath $KeyPath))    { Fail "Chave AES não encontrada em: $KeyPath" }

# Desbloqueia o script alvo silenciosamente
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# -------------------------------
# Leitura da chave AES
# -------------------------------
try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
} catch {
    Fail "Falha ao ler a chave AES ($KeyPath): $($_.Exception.Message)"
}

# -------------------------------
# Leitura das credenciais
# -------------------------------
$user = $null
$enc  = $null

try {
    $raw = Get-Content -LiteralPath $CredPath -Raw -ErrorAction Stop
} catch {
    Fail "Falha ao ler o arquivo de credenciais: $($_.Exception.Message)"
}

if ($raw -match '<\s*Credenciais\b') {
    # XML manual
    try {
        [xml]$xml = $raw
        $user = $xml.Credenciais.UserName
        $enc  = $xml.Credenciais.EncryptedPassword
    } catch {
        Fail "XML de credenciais inválido: $($_.Exception.Message)"
    }
} else {
    # Export-Clixml
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

# -------------------------------
# Reconstrução do PSCredential
# -------------------------------
try {
    $secure = ConvertTo-SecureString -String $enc -Key $keyBytes
} catch {
    Fail "Falha ao descriptografar a senha (key.bin incompatível)."
}

# Qualifica usuário local se necessário
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
$argList = @(
    '-ExecutionPolicy','Bypass',
    '-NoProfile',
    '-File', $ScriptPath
)

if ($NonInteractive) {
    $argList += '-NonInteractive'
}

# ---- Repasse de parâmetros do Guardian ----

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

if ($Simulado) {
    $argList += '-Simulado'
}

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
# Diretório de trabalho seguro
# -------------------------------
try {
    $workDir = Split-Path -Path $ScriptPath -Parent
} catch {
    $workDir = (Get-Location).Path
}

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

    Write-Host "Guardian iniciado com sucesso. PID: $($proc.Id)"
} catch {
    Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
}
