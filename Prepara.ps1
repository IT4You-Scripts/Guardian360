
<#
.SYNOPSIS
    Verifica e corrige Winget, instala PowerShell 7, ajusta PATH, cria alias, restaura politicas e valida associacao .ps1.
.DESCRIPTION
    Script corporativo com saida limpa e resumo final.
.NOTES
    Autor: [Seu Nome]
    Data: 19/01/2026
#>

function Show-Message {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# ==========================
# Validacao de Administrador
# ==========================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Show-Message "ERRO: Este script precisa ser executado como ADMINISTRADOR para aplicar todas as configuracoes." "Red"
    Show-Message "DICA: Clique com o botao direito no PowerShell e selecione 'Executar como administrador'." "Yellow"
    exit
}

# Variaveis de status
$WingetStatus = $PowerShellStatus = $PathStatus = $AliasStatus = $AssocStatus = $PolicyStatus = "FALHOU"

# ==========================
# Funcoes Winget
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
# Execucao Winget
# ==========================
Show-Message "===== Verificando Winget =====" "Cyan"
if (-not (Test-Winget)) {
    Show-Message "Winget com problemas. Reparando..." "Yellow"
    Remove-Winget
    Install-Winget
}
if (Test-Winget) {
    Show-Message "Winget OK" "Green"
    $WingetStatus = "OK"
} else {
    Show-Message "Winget falhou" "Red"
}

# ==========================
# Instala PowerShell 7
# ==========================
Show-Message "===== Instalando PowerShell 7 =====" "Cyan"
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
Start-Sleep -Seconds 5
if (Test-Path $pwshPath) {
    Show-Message "PowerShell 7 OK" "Green"
    $PowerShellStatus = "OK"
} else {
    Show-Message "PowerShell nao encontrado" "Red"
}

# ==========================
# Ajustes no PATH
# ==========================
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*PowerShell\7*") {
    $newPath = "$envPath;$($pwshPath.Substring(0,$pwshPath.LastIndexOf('\')))"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    Show-Message "PATH atualizado" "Green"
    $PathStatus = "OK"
} else {
    Show-Message "PATH ja contem PowerShell 7" "Yellow"
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
    Show-Message "Alias criado no perfil do PowerShell" "Green"
    $AliasStatus = "OK"
} catch {
    Show-Message "Erro ao criar alias" "Red"
}

# ==========================
# Associacao .ps1
# ==========================
Show-Message "Associando arquivos .ps1 ao PowerShell 7..." "Yellow"

Start-Process -FilePath "cmd.exe" -ArgumentList '/c assoc .ps1=Microsoft.PowerShellScript.1' -NoNewWindow -Wait

# Comando ftype concatenado corretamente
$ftypeCmd = '/c ftype Microsoft.PowerShellScript.1="' + $pwshPath + '" -NoExit -Command "%1"'
Start-Process -FilePath "cmd.exe" -ArgumentList $ftypeCmd -NoNewWindow -Wait

# Validacao
$assocResult = cmd /c assoc .ps1
$ftypeResult = cmd /c ftype Microsoft.PowerShellScript.1
if ($assocResult -like "*.ps1=*Microsoft.PowerShellScript.1*" -and $ftypeResult -like "*pwsh.exe*") {
    Show-Message "Associacao .ps1 OK" "Green"
    $AssocStatus = "OK"
} else {
    Show-Message "Associacao falhou" "Red"
}

# ==========================
# Restaurar politicas
# ==========================
Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser -Force
Set-ExecutionPolicy Undefined -Scope Process -Force
Set-ExecutionPolicy RemoteSigned -Force
Show-Message "Politicas restauradas" "Green"
$PolicyStatus = "OK"

# ==========================
# Resumo Final
# ==========================
Show-Message "`n===== RESUMO FINAL =====" "Cyan"
Show-Message "Winget: $WingetStatus" "Green"
Show-Message "PowerShell 7: $PowerShellStatus" "Green"
Show-Message "PATH: $PathStatus" "Green"
Show-Message "Alias: $AliasStatus" "Green"
Show-Message "Associacao .ps1: $AssocStatus" "Green"
Show-Message "Politicas: $PolicyStatus" "Green"
Show-Message "Script concluido com sucesso!" "Green"

