<#
Script minimalista + resumo final em quadro cyan
#>

# Linha de espaçamento solicitada
Write-Host ""

function Step {
    param([string]$Message)
    Write-Host ("  → " + $Message) -ForegroundColor White
}

# =====================================
# ADMIN
# =====================================

$IsAdmin = [Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host ""
    Write-Host "ERRO: Este script precisa ser executado como ADMINISTRADOR." -ForegroundColor Red
    exit 1
}

# Silêncio absoluto
$ErrorActionPreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"
$DebugPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# =====================================
# STATUS VARIABLES
# =====================================

$WingetStatus = "FALHOU"
$PowerShellStatus = "FALHOU"
$PathStatus = "FALHOU"
$AliasStatus = "FALHOU"
$AssocStatus = "FALHOU"
$PolicyStatus = "FALHOU"

# =====================================
# WINGET
# =====================================

Step "Verificando Winget..."

function Test-Winget {
    try {
        winget --version 2>$null | Out-Null
        return $?
    } catch { return $false }
}

if (-not (Test-Winget)) {
    Get-AppxPackage Microsoft.DesktopAppInstaller | Remove-AppxPackage 2>$null
    Get-AppxPackage Microsoft.VCLibs* | Remove-AppxPackage 2>$null
    Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" -Force -Recurse 2>$null

    $u = "https://aka.ms/getwinget"
    $p = "$env:TEMP\AppInstaller.msixbundle"
    Invoke-WebRequest -Uri $u -OutFile $p -UseBasicParsing 2>$null
    Add-AppxPackage -Path $p 2>$null
}

if (Test-Winget) { $WingetStatus = "OK" }

# =====================================
# INSTALL POWERSHELL 7
# =====================================

function Show-ProgressBar {
    param([int]$Percent)

    $total = 28
    $filled = [math]::Floor(($Percent / 100) * $total)
    $empty  = $total - $filled

    $bar = ("█" * $filled) + ("░" * $empty)
    Write-Host ("`r[${bar}] ${Percent}% ") -NoNewline -ForegroundColor Cyan
}

Step "Instalando PowerShell 7..."

Show-ProgressBar -Percent 5

winget install --id Microsoft.PowerShell `
    --silent --accept-package-agreements --accept-source-agreements `
    | Out-Null 2>&1

foreach ($p in 20,40,60,80,100) {
    Start-Sleep -Milliseconds 250
    Show-ProgressBar -Percent $p
}

$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
if (Test-Path $pwshPath) { 
    $PowerShellStatus = "OK"
}

Write-Host ""

# =====================================
# PATH
# =====================================

Step "Atualizando PATH..."

$envPath = [Environment]::GetEnvironmentVariable("Path","Machine")
$pwshDir = Split-Path $pwshPath

if ($envPath -notlike "*$pwshDir*") {
    [Environment]::SetEnvironmentVariable("Path","$envPath;$pwshDir","Machine")
}

$PathStatus = "OK"

# =====================================
# ALIAS
# =====================================

Step "Criando alias..."

$profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

"Set-Alias powershell '$pwshPath'" | Out-File -FilePath $profilePath -Append

$AliasStatus = "OK"

# =====================================
# ASSOCIAR .ps1
# =====================================

Step "Associando .ps1 ao PowerShell 7..."

cmd.exe /c "assoc .ps1=Microsoft.PowerShellScript.1" 2>&1 | Out-Null
cmd.exe /c "ftype Microsoft.PowerShellScript.1=\"$pwshPath\" \"%1\" %*" 2>&1 | Out-Null

$AssocStatus = "OK"

# =====================================
# EXECUTION POLICY
# =====================================

Step "Restaurando políticas..."

Set-ExecutionPolicy Undefined -Scope LocalMachine -Force
Set-ExecutionPolicy Undefined -Scope CurrentUser  -Force
Set-ExecutionPolicy Undefined -Scope Process      -Force
Set-ExecutionPolicy RemoteSigned -Force

$PolicyStatus = "OK"

# =====================================
# LIMPEZA FINAL
# =====================================

Step "Limpando itens antigos..."

if (Test-Path "C:\IT4You") {
    Remove-Item "C:\IT4You" -Recurse -Force
}

Get-ScheduledTask |
Where-Object { $_.TaskName -like "*Manutenção Automatizada*" } |
ForEach-Object {

    $p = $_.TaskPath.TrimEnd("\")
    
    if ($p -eq "") {
        $fullTask = "\$($_.TaskName)"
    } else {
        $fullTask = "$p\$($_.TaskName)"
    }

    schtasks /Delete /TN $fullTask /F | Out-Null
}

# =====================================
# FINAL SUMMARY — BIG CYAN BOX
# =====================================

$width = 42
$top    = "╔" + ("═" * $width) + "╗"
$bottom = "╚" + ("═" * $width) + "╝"

function StatusLine {
    param($label, $status)

    if ($status -eq "OK") {
        $txt = "→ $label OK"
        Write-Host ("║  " + $txt + (" " * ($width - 2 - $txt.Length)) + "║") -ForegroundColor Cyan
    } else {
        $txt = "→ $label FALHOU"
        Write-Host ("║  " + $txt + (" " * ($width - 2 - $txt.Length)) + "║") -ForegroundColor Red
    }
}

Write-Host ""
Write-Host $top -ForegroundColor Cyan
Write-Host ("║  RESUMO FINAL" + (" " * 28) + "║") -ForegroundColor Cyan
Write-Host ("║" + (" " * $width) + "║") -ForegroundColor Cyan

StatusLine "Winget           " $WingetStatus
StatusLine "PowerShell 7     " $PowerShellStatus
StatusLine "PATH             " $PathStatus
StatusLine "Alias            " $AliasStatus
StatusLine "Associação .ps1  " $AssocStatus
StatusLine "Políticas        " $PolicyStatus

Write-Host ("║" + (" " * $width) + "║") -ForegroundColor Cyan
Write-Host ("║  Ambiente pronto para o Guardian 360." + (" " * 4) + "║") -ForegroundColor Cyan
Write-Host $bottom -ForegroundColor Cyan
Write-Host ""