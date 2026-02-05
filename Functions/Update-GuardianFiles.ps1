function Update-GuardianFiles {

    $ErrorActionPreference = "Stop"
    $ProgressPreference   = "SilentlyContinue"

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

    # Configurações
    $BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
    $BasePath  = "C:\Guardian"

    # Cache busting permanente (ANTI GitHub RAW cache)
    $NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Estrutura base (nunca apaga nada)
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

    # -------------------------------
    # Lista de arquivos oficiais
    # -------------------------------
    $Files = @(
        # Baixar versão nova sem sobrescrever a atual
        @{ Url = "$BaseUrl/RodaGuardian.ps1";                        Path = "$BasePath\RodaGuardian.new" },
        @{ Url = "$BaseUrl/ElevaGuardian.ps1";                       Path = "$BasePath\ElevaGuardian.new" },
        @{ Url = "$BaseUrl/Update-GuardianFiles.ps1";                Path = "$BasePath\Update-GuardianFiles.new" },
        
        # Baixar versão nova sobrescrevendo as atuais
        @{ Url = "$BaseUrl/Atualiza.ps1";                            Path = "$BasePath\Atualiza.ps1" },
        @{ Url = "$BaseUrl/CriaCredenciais.ps1";                     Path = "$BasePath\CriaCredenciais.ps1" },
        @{ Url = "$BaseUrl/Guardian.ps1";                            Path = "$BasePath\Guardian.ps1" },
        @{ Url = "$BaseUrl/Prepara.ps1";                             Path = "$BasePath\Prepara.ps1" },
        @{ Url = "$BaseUrl/Assets/Images/logotipo.png";              Path = "$BasePath\Assets\Images\logotipo.png" },
        @{ Url = "$BaseUrl/Assets/Images/guardian_bg.png";           Path = "$BasePath\Assets\Images\guardian_bg.png" },
        @{ Url = "$BaseUrl/Assets/Images/guardian_end_bg.png";       Path = "$BasePath\Assets\Images\guardian_end_bg.png" },
        @{ Url = "$BaseUrl/Functions/Block-AppUpdates.ps1";          Path = "$BasePath\Functions\Block-AppUpdates.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-AllRecycleBins.ps1";      Path = "$BasePath\Functions\Clear-AllRecycleBins.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-BrowserCache.ps1";        Path = "$BasePath\Functions\Clear-BrowserCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-RecentFilesHistory.ps1";  Path = "$BasePath\Functions\Clear-RecentFilesHistory.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-TempFiles.ps1";           Path = "$BasePath\Functions\Clear-TempFiles.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-WindowsUpdateCache.ps1";  Path = "$BasePath\Functions\Clear-WindowsUpdateCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Confirm-MacriumBackup.ps1";     Path = "$BasePath\Functions\Confirm-MacriumBackup.ps1" },
        @{ Url = "$BaseUrl/Functions/Get-SystemInventory.ps1";       Path = "$BasePath\Functions\Get-SystemInventory.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-HDD.ps1";              Path = "$BasePath\Functions\Optimize-HDD.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-JsonReport.ps1";       Path = "$BasePath\Functions\Optimize-JsonReport.ps1" },
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
        @{ Url = "$BaseUrl/Functions/Update-WingetApps.ps1";         Path = "$BasePath\Functions\Update-WingetApps.ps1" },
        @{ Url = "$BaseUrl/Functions/Write-JsonResult.ps1";          Path = "$BasePath\Functions\Write-JsonResult.ps1" }
    )

    # --------------------------------------------------------------
    # Limpeza dos atributos Read-Only (caso existam)
    # --------------------------------------------------------------
    Show-Header "Baixando arquivos do Guardian 360..." -Color Yellow

    foreach ($File in $Files) {
        try {
            if (Test-Path $File.Path) {

                # Remove atributo ReadOnly
                attrib -R $File.Path 2>$null
            }
        }
        catch {
            Write-Host "Aviso: Não foi possível mudar os atributos dos arquivos $($File.Path)" -ForegroundColor DarkYellow
        }
    }

    # -------------------------------
    # DOWNLOAD ATUALIZADO
    # -------------------------------
    Show-Header "Atualizando Guardian 360..." -Color Cyan

    foreach ($File in $Files) {
        try {
            Invoke-WebRequest `
                -Uri "$($File.Url)$NoCache" `
                -OutFile $File.Path `
                -UseBasicParsing `
                -Headers @{ "Cache-Control"="no-cache" } `
                -ErrorAction Stop
        }
        catch {

            # Se for imagem, só avisa
            if ($File.Path -match "\.png$") {
                Write-Host "Aviso: Falha ao baixar imagem $($File.Path)" -ForegroundColor DarkYellow
                continue
            }

            # Se for script, falha crítica
            Fail "Falha crítica ao atualizar: $($File.Path)"
        }
    }
  
# Atualização dos aqruivos que estavam na nmemória
$AtomicTargets = @(
    @{ New = "$BasePath\RodaGuardian.new";                    Final = "$BasePath\RodaGuardian.ps1" },
    @{ New = "$BasePath\ElevaGuardian.new";                   Final = "$BasePath\ElevaGuardian.ps1" },
    @{ New = "$BasePath\Update-GuardianFiles.new";            Final = "$BasePath\Update-GuardianFiles.ps1" }
)

foreach ($item in $AtomicTargets) {
    $src = $item.New
    $dst = $item.Final

    if (Test-Path $src) {

        try {
            attrib -R $dst 2>$null
            Move-Item -Force $src $dst
        }
        catch {
            Write-Host "Aviso: não foi possível atualizar $dst" -ForegroundColor DarkYellow
        }
    }
}

    # Final OK
    Show-Header "Atualização concluída com sucesso!" -Color Green
}