# ChamaManutencao.ps1
# Executa C:\Guardian\Scripts\Manutencao.ps1 em PowerShell 7 usando credenciais criptografadas (key.bin + credenciais.xml)

param (
    [string]$PwshPath   = 'C:\Program Files\PowerShell\7\pwsh.exe',
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',
    [string]$CredPath   = 'C:\Guardian\credenciais.xml',
    [string]$KeyPath    = 'C:\Guardian\key.bin',
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized
)

function Fail {
    param ([string]$msg)
    Write-Error $msg
    exit 1
}

# Validações de caminhos
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PS7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Script não encontrado em: $ScriptPath" }
if (-not (Test-Path -LiteralPath $CredPath))   { Fail "Credenciais não encontradas em: $CredPath" }
if (-not (Test-Path -LiteralPath $KeyPath))    { Fail "Chave AES não encontrada em: $KeyPath" }

# Desbloqueia o script alvo silenciosamente
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# Lê a chave
try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
} catch {
    Fail "Falha ao ler a chave em ${KeyPath}: $($_.Exception.Message)"
}

# Lê as credenciais (suporta XML manual e Export-Clixml)
$user = $null
$enc  = $null

try {
    $raw = Get-Content -LiteralPath $CredPath -Raw -ErrorAction Stop
} catch {
    Fail "Falha ao ler ${CredPath}: $($_.Exception.Message)"
}

if ($raw -match '<\s*Credenciais\b') {
    # Formato XML manual
    try {
        [xml]$xml = $raw
        $user = $xml.Credenciais.UserName
        $enc  = $xml.Credenciais.EncryptedPassword
    } catch {
        Fail "Arquivo de credenciais (XML manual) inválido: $($_.Exception.Message)"
    }
} else {
    # Tenta como Export-Clixml
    try {
        $data = Import-Clixml -Path $CredPath -ErrorAction Stop
        $user = $data.UserName
        $enc  = $data.EncryptedPassword
    } catch {
        Fail "Arquivo de credenciais não é XML esperado nem Clixml válido: $($_.Exception.Message)"
    }
}

if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($enc)) {
    Fail "Conteúdo de credenciais incompleto (UserName/EncryptedPassword)."
}

# Constrói SecureString e PSCredential
try {
    $secure = ConvertTo-SecureString -String $enc -Key $keyBytes
} catch {
    Fail "Falha ao converter senha criptografada (confira se a key.bin corresponde ao credenciais.xml): $($_.Exception.Message)"
}

# Qualifica usuário local sem usar regex (evita erro do padrão '\')
if ($user -notlike '*\*' -and $user -notlike '*@*') {
    $user = "$env:COMPUTERNAME\$user"
}

try {
    $cred = [System.Management.Automation.PSCredential]::new($user, $secure)
} catch {
    Fail "Falha ao construir PSCredential: $($_.Exception.Message)"
}

# Argumentos para PowerShell 7 (usar array evita problemas de aspas)
$argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File', $ScriptPath)
if ($NonInteractive) { $argList += '-NonInteractive' }

# Janela: NoWindow tem prioridade; caso contrário, maximiza se solicitado
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# Diretório de trabalho: usar Split-Path corretamente e garantir fallback
$workDir = $null
try {
    $workDir = Split-Path -Path $ScriptPath -Parent
} catch {
    $workDir = $null
}
if (-not $workDir) {
    # Fallback para a pasta do pwsh ou, se falhar, para o diretório atual
    try { $workDir = Split-Path -Path $PwshPath -Parent } catch { $workDir = (Get-Location).Path }
}

# Observação: Start-Process -Credential não força elevação UAC. Se o Manutencao.ps1 exigir privilégios elevados,
# considere rodar via Tarefa Agendada com “Executar com os privilégios mais altos”.

try {
    $p = Start-Process -FilePath $PwshPath -ArgumentList $argList -Credential $cred -WorkingDirectory $workDir -WindowStyle $winStyle -UseNewEnvironment -PassThru
    Write-Host "Processo iniciado. PID: $($p.Id)"
} catch {
    Fail "Falha ao iniciar processo no PS7: $($_.Exception.Message)"
}