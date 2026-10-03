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
$RustDeskStatus = "FALHOU"

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
# RUSTDESK — PREPARACAO ANTECIPADA
# =====================================

Step "Preparando RustDesk..."

$RustDeskServer  = "rustdesk.it4you.com.br"
$RustDeskKey     = "t5GEz58onhVjOdwom7336p+EWy8iXtIcuXrzo3YTwyU="
$RustDeskDir     = "C:\Program Files\RustDesk"
$RustDeskExe     = Join-Path $RustDeskDir "rustdesk.exe"
$RustDeskService = "RustDesk"
$ConfigDir       = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config"
$Config2File     = Join-Path $ConfigDir "RustDesk2.toml"
$DownloadTimeout = 120
$GitHubApiUrl    = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

function Test-RustDeskConfig {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) { return $false }

    $conteudo = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $conteudo) { return $false }

    if ($conteudo -match "key\s*=\s*'([^']*)'") {
        $keyNoArquivo = $Matches[1]
    }
    else {
        return $false
    }

    if ($conteudo -match "custom-rendezvous-server\s*=\s*'([^']*)'") {
        $serverNoArquivo = $Matches[1]
    }
    else {
        return $false
    }

    if ($keyNoArquivo -ne $RustDeskKey) { return $false }
    if ($serverNoArquivo -ne $RustDeskServer) { return $false }

    return $true
}

try {
    # -------------------------------------------------
    # 1. Instalar somente se ainda nao existir
    # -------------------------------------------------
    if (-not (Test-Path $RustDeskExe)) {

        Write-Host "  → RustDesk não encontrado. Instalando silenciosamente..." -ForegroundColor Yellow

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $releaseInfo = Invoke-RestMethod `
                -Uri $GitHubApiUrl `
                -TimeoutSec 30 `
                -ErrorAction Stop

            $asset = $releaseInfo.assets | Where-Object {
                $_.name -match "rustdesk-.*-x86_64\.exe$" -and
                $_.name -notmatch "portable"
            } | Select-Object -First 1

            if ($asset) {

                $installerPath = "C:\Windows\Temp\rustdesk_installer.exe"

                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

                Invoke-WebRequest `
                    -Uri $asset.browser_download_url `
                    -OutFile $installerPath `
                    -TimeoutSec $DownloadTimeout `
                    -ErrorAction Stop

                if (Test-Path $installerPath) {

                    Start-Process `
                        -FilePath $installerPath `
                        -ArgumentList "--silent-install"

                    # Mesmo criterio ja usado no Manage-RustDesk:
                    # aguardar o executavel aparecer.
                    $tentativas = 0
                    $maxTentativas = 12

                    while (-not (Test-Path $RustDeskExe) -and $tentativas -lt $maxTentativas) {
                        Start-Sleep -Seconds 10
                        $tentativas++
                    }

                    # Aguardar um pouco pela criacao do servico.
                    # Se ele ainda nao existir, o Prepara segue normalmente;
                    # o Guardian fara a validacao definitiva mais tarde.
                    $tentativas = 0

                    while (-not (Get-Service $RustDeskService -ErrorAction SilentlyContinue) -and $tentativas -lt 6) {
                        Start-Sleep -Seconds 5
                        $tentativas++
                    }

                    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            # O Guardian continuara sendo a validacao definitiva.
        }
    }

    # -------------------------------------------------
    # 2. Configurar antecipadamente servidor / relay / key
    # -------------------------------------------------
    if (Test-Path $RustDeskExe) {

        $usersDir = "C:\Users"

        $config2Content = @"
rendezvous_server = '$RustDeskServer'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '$RustDeskServer'
relay-server = '$RustDeskServer'
key = '$RustDeskKey'
"@

        function Test-AllRustDeskConfigs {

            if (-not (Test-RustDeskConfig -FilePath $Config2File)) {
                return $false
            }

            foreach ($userDir in (
                Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue
            )) {

                $roamingDir = Join-Path $userDir.FullName "AppData\Roaming"

                if (Test-Path $roamingDir) {

                    $userConfig2Path = Join-Path `
                        $userDir.FullName `
                        "AppData\Roaming\RustDesk\config\RustDesk2.toml"

                    if (-not (Test-RustDeskConfig -FilePath $userConfig2Path)) {
                        return $false
                    }
                }
            }

            return $true
        }

        $precisaConfigurar = -not (Test-AllRustDeskConfigs)

        if ($precisaConfigurar) {

            $configuracaoConfirmada = $false
            $maxTentativasConfig = 3

            for (
                $tentativaConfig = 1;
                $tentativaConfig -le $maxTentativasConfig;
                $tentativaConfig++
            ) {

                Stop-Service -Name $RustDeskService -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                if (-not (Test-Path $ConfigDir)) {
                    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
                }

                Set-Content `
                    -Path $Config2File `
                    -Value $config2Content `
                    -Force `
                    -Encoding UTF8

                Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {

                    $roamingDir = Join-Path $_.FullName "AppData\Roaming"

                    if (Test-Path $roamingDir) {

                        $userConfigDir = Join-Path `
                            $_.FullName `
                            "AppData\Roaming\RustDesk\config"

                        if (-not (Test-Path $userConfigDir)) {
                            New-Item `
                                -ItemType Directory `
                                -Path $userConfigDir `
                                -Force | Out-Null
                        }

                        $userConfig2 = Join-Path `
                            $userConfigDir `
                            "RustDesk2.toml"

                        Set-Content `
                            -Path $userConfig2 `
                            -Value $config2Content `
                            -Force `
                            -Encoding UTF8
                    }
                }

                Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5

                if (Test-AllRustDeskConfigs) {
                    $configuracaoConfirmada = $true
                    break
                }

                Start-Sleep -Seconds 3
            }
        }
        else {
            $configuracaoConfirmada = $true
        }

        # -------------------------------------------------
        # 3. Deixar o servico iniciado e validar o preparo
        # -------------------------------------------------
        Start-Service -Name $RustDeskService -ErrorAction SilentlyContinue

        if (Test-AllRustDeskConfigs) {
            $RustDeskStatus = "OK"
        }
    }
}
catch {
    # Mantem o comportamento silencioso do Prepara.
    # O Manage-RustDesk do Guardian fara nova tentativa no final.
}


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
StatusLine "RustDesk         " $RustDeskStatus
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