
<#
.SYNOPSIS
    Verifica e corrige Winget, instala PowerShell 7, ajusta PATH, cria alias, restaura políticas e valida associaçãoo .ps1.
.DESCRIPTION
    Script corporativo com saída limpa e resumo final.
.NOTES
    Autor: [Seu Nome]
    Data: 19/01/2026
#>

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
# Função para mensagens simples
# -------------------------------
function Show-Message {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
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

# ==========================
# Validação de Administrador
# ==========================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Fail "ERRO: Este script precisa ser executado como ADMINISTRADOR para aplicar todas as configurações.
DICA: Clique com o botão direito no PowerShell e selecione 'Executar como administrador'."
}

# Variáveis de status
$WingetStatus = $PowerShellStatus = $PathStatus = $AliasStatus = $AssocStatus = $PolicyStatus = "FALHOU"

# ==========================
# Funções Winget
# ==========================
function Test-Winget {
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) { return $false }
        $result = winget list --source winget 2>$null
        return $result -ne $null
    } catch { return $false }
}

function Remove-Winget {
    Get-AppxPackage Microsoft.DesktopAppInstaller | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxPackage Microsoft.VCLibs* | Remove-AppxPackage -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-Winget {
    $InstallerUrl = "https://aka.ms/getwinget"
    $InstallerPath = "$env:TEMP\AppInstaller.msixbundle"
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
    Add-AppxPackage -Path $InstallerPath -ErrorAction Stop
}

# ==========================
# Execução do Winget
# ==========================
Show-Header "Verificando Winget" -Color Cyan
if (-not (Test-Winget)) {
    Show-Header "Winget com problemas. Reparando..." -Color Yellow
    Remove-Winget
    Install-Winget
}
if (Test-Winget) {
    Show-Header "Winget OK" -Color Green
    $WingetStatus = "OK"
} else {
    Fail "Winget falhou"
}

# ==========================
# Instala PowerShell 7
# ==========================
Show-Header "Instalando PowerShell 7" -Color Cyan
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
Start-Sleep -Seconds 5
if (Test-Path $pwshPath) {
    Show-Header "PowerShell 7 OK" -Color Green
    $PowerShellStatus = "OK"
} else {
    Fail "PowerShell não encontrado"
}

# ==========================
# Ajustes no PATH
# ==========================
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*PowerShell\7*") {
    $newPath = "$envPath;$($pwshPath.Substring(0,$pwshPath.LastIndexOf('\')))"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Show-Header "PATH atualizado" -Color Green
    $PathStatus = "OK"
} else {
    Show-Header "PATH já contém PowerShell 7" -Color Yellow
    $PathStatus = "OK"
}

# ==========================
# Alias via perfil do PowerShell
# ==========================
try {
    $profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force
    }
    Add-Content -Path $profilePath -Value "Set-Alias powershell '$pwshPath'"
    Show-Header "Alias criado no perfil do PowerShell" -Color Green
    $AliasStatus = "OK"
} catch {
    Fail "Erro ao criar alias"
}

# ==========================
# Associação .ps1
# ==========================
Show-Header "Associando arquivos .ps1 ao PowerShell 7..." -Color Yellow

Start-Process -FilePath "cmd.exe" -ArgumentList '/c assoc .ps1=Microsoft.PowerShellScript.1' -NoNewWindow -Wait

$ftypeCmd = '/c ftype Microsoft.PowerShellScript.1="' + $pwshPath + '" -NoExit -Command "%1"'
Start-Process -FilePath "cmd.exe" -ArgumentList $ftypeCmd -NoNewWindow -Wait

$assocResult = cmd /c assoc .ps1
$ftypeResult = cmd /c ftype Microsoft.PowerShellScript.1
if ($assocResult -like "*.ps1=*Microsoft.PowerShellScript.1*" -and $ftypeResult -like "*pwsh.exe*") {
    Show-Header "Associação .ps1 OK" -Color Green
    $AssocStatus = "OK"
} else {
    Fail "Associação falhou"
}

# ==========================
# Restaurar políticas
# ==========================
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force
Show-Header "Políticas restauradas" -Color Green
$PolicyStatus = "OK"

# ==========================
# Resumo Final
# ==========================
Show-Header "===== RESUMO FINAL =====" -Color Cyan
Show-Message "Winget: $WingetStatus" "Green"
Show-Message "PowerShell 7: $PowerShellStatus" "Green"
Show-Message "PATH: $PathStatus" "Green"
Show-Message "Alias: $AliasStatus" "Green"
Show-Message "Associação .ps1: $AssocStatus" "Green"
Show-Message "Políticas: $PolicyStatus" "Green"
Show-Header "Script concluído com sucesso!" -Color Green
