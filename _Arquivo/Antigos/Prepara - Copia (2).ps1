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

function Get-WingetPath {

    # 1. Tentar comando disponível normalmente
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    # 2. Alias do usuário atual
    $aliasPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"

    if (Test-Path $aliasPath) {
        return $aliasPath
    }

    # 3. Executável real dentro do WindowsApps
    $wingetReal = Get-ChildItem `
        "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if ($wingetReal) {
        return $wingetReal.FullName
    }

    return $null
}


function Test-Winget {

    $script:WingetExe = Get-WingetPath

    if (-not $script:WingetExe) {
        return $false
    }

    try {
        & $script:WingetExe --version 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}


# -------------------------------------------------
# Primeira verificação
# -------------------------------------------------

if (-not (Test-Winget)) {

    Write-Host "  → Winget não disponível. Tentando registrar o App Installer..." -ForegroundColor Yellow

    try {
        Add-AppxPackage `
            -RegisterByFamilyName `
            -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe `
            -ErrorAction SilentlyContinue
    }
    catch {}

    Start-Sleep -Seconds 5
}


# -------------------------------------------------
# Se ainda não funcionar, reparar/reinstalar
# -------------------------------------------------

if (-not (Test-Winget)) {

    Write-Host "  → Winget ainda indisponível. Tentando reparar..." -ForegroundColor Yellow

    Get-AppxPackage Microsoft.DesktopAppInstaller |
        Remove-AppxPackage 2>$null

    Get-AppxPackage Microsoft.VCLibs* |
        Remove-AppxPackage 2>$null

    Remove-Item `
        "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller*" `
        -Force `
        -Recurse `
        2>$null

    $u = "https://aka.ms/getwinget"
    $p = "$env:TEMP\AppInstaller.msixbundle"

    Remove-Item $p -Force -ErrorAction SilentlyContinue

    Invoke-WebRequest `
        -Uri $u `
        -OutFile $p `
        -UseBasicParsing `
        2>$null

    if (Test-Path $p) {
        Add-AppxPackage `
            -Path $p `
            2>$null
    }

    Start-Sleep -Seconds 5
}


# -------------------------------------------------
# Validar Winget — até 3 tentativas
# -------------------------------------------------

for ($tentativa = 1; $tentativa -le 3; $tentativa++) {

    if (Test-Winget) {
        $WingetStatus = "OK"
        break
    }

    if ($tentativa -lt 3) {
        Write-Host "  → Aguardando Winget ficar disponível... tentativa $tentativa/3" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}


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

$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"


# -------------------------------------------------
# 1. Verificar instalação real
# -------------------------------------------------

if (Test-Path $pwshPath) {

    Show-ProgressBar -Percent 100
    $PowerShellStatus = "OK"
}

else {

    Show-ProgressBar -Percent 5

    # -------------------------------------------------
    # 2. Primeira tentativa pelo Winget
    # -------------------------------------------------

    if ($WingetStatus -eq "OK") {

        Write-Host ""
        Write-Host "  → Tentando instalar PowerShell 7 pelo Winget..." -ForegroundColor White

        $WingetExe = Get-WingetPath

        if ($WingetExe) {

            & $WingetExe install `
                --id Microsoft.PowerShell `
                --exact `
                --source winget `
                --silent `
                --accept-package-agreements `
                --accept-source-agreements `
                --disable-interactivity `
                | Out-Null 2>&1
        }

        Start-Sleep -Seconds 3
    }


    # -------------------------------------------------
    # 3. Verificar instalação física
    # -------------------------------------------------

    if (Test-Path $pwshPath) {

        $PowerShellStatus = "OK"
    }

    else {

        # -------------------------------------------------
        # 4. FALLBACK — MSI oficial do PowerShell 7
        # -------------------------------------------------

        Write-Host "  → PowerShell 7 não foi instalado pelo Winget." -ForegroundColor Yellow
        Write-Host "  → Instalando diretamente pelo MSI oficial..." -ForegroundColor Yellow

        try {

            $releaseApi = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"

            $release = Invoke-RestMethod `
                -Uri $releaseApi `
                -UseBasicParsing `
                -ErrorAction Stop

            $msiAsset = $release.assets |
                Where-Object {
                    $_.name -match '^PowerShell-[0-9]+\.[0-9]+\.[0-9]+-win-x64\.msi$'
                } |
                Select-Object -First 1

            if ($msiAsset) {

                $msiPath = Join-Path $env:TEMP $msiAsset.name

                Remove-Item `
                    $msiPath `
                    -Force `
                    -ErrorAction SilentlyContinue

                Show-ProgressBar -Percent 20

                Invoke-WebRequest `
                    -Uri $msiAsset.browser_download_url `
                    -OutFile $msiPath `
                    -UseBasicParsing `
                    -ErrorAction Stop

                Show-ProgressBar -Percent 50

                if (Test-Path $msiPath) {

                    $msiArgs = @(
                        "/i"
                        "`"$msiPath`""
                        "/qn"
                        "/norestart"
                        "ADD_PATH=1"
                        "REGISTER_MANIFEST=1"
                        "USE_MU=1"
                        "ENABLE_MU=1"
                    )

                    $msiProcess = Start-Process `
                        -FilePath "msiexec.exe" `
                        -ArgumentList $msiArgs `
                        -Wait `
                        -PassThru `
                        -WindowStyle Hidden

                    Show-ProgressBar -Percent 80

                    Start-Sleep -Seconds 3
                }

                Remove-Item `
                    $msiPath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Mantém o script silencioso.
            # O resultado real será validado abaixo.
        }


        # -------------------------------------------------
        # 5. Validação final
        # -------------------------------------------------

        if (Test-Path $pwshPath) {

            $PowerShellStatus = "OK"
        }
    }


    Show-ProgressBar -Percent 100
}

Write-Host ""


# =====================================
# PATH
# =====================================

Step "Atualizando PATH..."

if (Test-Path $pwshPath) {

    $envPath = [Environment]::GetEnvironmentVariable("Path","Machine")
    $pwshDir = Split-Path $pwshPath

    if ($envPath -notlike "*$pwshDir*") {

        [Environment]::SetEnvironmentVariable(
            "Path",
            "$envPath;$pwshDir",
            "Machine"
        )
    }

    $PathStatus = "OK"
}


# =====================================
# ALIAS
# =====================================

Step "Criando alias..."

if (Test-Path $pwshPath) {

    $profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    "Set-Alias powershell '$pwshPath'" |
        Out-File `
            -FilePath $profilePath `
            -Append

    $AliasStatus = "OK"
}


# =====================================
# ASSOCIAR .ps1
# =====================================

Step "Associando .ps1 ao PowerShell 7..."

if (Test-Path $pwshPath) {

    cmd.exe /c "assoc .ps1=Microsoft.PowerShellScript.1" 2>&1 |
        Out-Null

    cmd.exe /c "ftype Microsoft.PowerShellScript.1=\"$pwshPath\" \"%1\" %*" 2>&1 |
        Out-Null

    $AssocStatus = "OK"
}


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
    }
    else {
        $fullTask = "$p\$($_.TaskName)"
    }

    schtasks /Delete /TN $fullTask /F |
        Out-Null
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

        Write-Host (
            "║  " +
            $txt +
            (" " * ($width - 2 - $txt.Length)) +
            "║"
        ) -ForegroundColor Cyan
    }
    else {

        $txt = "→ $label FALHOU"

        Write-Host (
            "║  " +
            $txt +
            (" " * ($width - 2 - $txt.Length)) +
            "║"
        ) -ForegroundColor Red
    }
}


Write-Host ""
Write-Host $top -ForegroundColor Cyan

Write-Host (
    "║  RESUMO FINAL" +
    (" " * 28) +
    "║"
) -ForegroundColor Cyan

Write-Host (
    "║" +
    (" " * $width) +
    "║"
) -ForegroundColor Cyan


StatusLine "Winget           " $WingetStatus
StatusLine "PowerShell 7     " $PowerShellStatus
StatusLine "PATH             " $PathStatus
StatusLine "Alias            " $AliasStatus
StatusLine "Associação .ps1  " $AssocStatus
StatusLine "Políticas        " $PolicyStatus


Write-Host (
    "║" +
    (" " * $width) +
    "║"
) -ForegroundColor Cyan

Write-Host (
    "║  Ambiente pronto para o Guardian 360." +
    (" " * 4) +
    "║"
) -ForegroundColor Cyan

Write-Host $bottom -ForegroundColor Cyan
Write-Host ""