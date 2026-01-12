# Atualiza o Windows
function Update-WindowsSystem {
    [CmdletBinding()]
    param()

    # Suprimir qualquer confirmação, barra de progresso e verboses
    $ConfirmPreference                    = 'None'
    $PSDefaultParameterValues['*:Confirm'] = $false
    $ProgressPreference                   = 'SilentlyContinue'
    $VerbosePreference                    = 'SilentlyContinue'
    $ErrorActionPreference                = 'Stop'

    # Write-Log opcional: se não existir, define NO-OP
    if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        function Write-Log { param([string]$m) ; return }
    }

    # Utilitário para checar reinício necessário via Registro (independente do módulo)
    function Test-RebootRequired {
        return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    }

    Write-Log ""
    Write-Log "Iniciando Invoke-SmartWindowsUpdate (WUA/COM, sem prompts)."
    Write-Log ""

    try {
        # ---------------------------------------------------------
        # (Opcional) Registrar Microsoft Update via COM, silencioso
        # Evita Add-WUServiceManager/ShouldProcess (sem perguntas)
        # ---------------------------------------------------------
        try {
            $muGuid = '7971f918-a847-4430-9279-4a52d1efe18d'  # Microsoft Update GUID
            $svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
            $hasMU  = $false
            foreach ($svc in @($svcMgr.Services)) {
                if ($svc.ServiceID -eq $muGuid) { $hasMU = $true; break }
            }
            if (-not $hasMU) {
                # Flags '7' (permite registro silencioso, sem UI). Se falhar, ignore.
                $null = $svcMgr.AddService2($muGuid, 7, 'Invoke-SmartWindowsUpdate')
                Write-Log "Microsoft Update registrado via COM (silencioso)."
            }
        } catch {
            Write-Log "Registro do Microsoft Update via COM falhou/suprimido: $($_.Exception.Message)"
        }

        # ---------------------------------------------------------
        # Busca, download e instalação de updates via WUA/COM
        # ---------------------------------------------------------
        # Cria sessão COM do Windows Update
        $session                       = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID   = 'Invoke-SmartWindowsUpdate'

        # Busca online por atualizações não instaladas e não ocultas
        $searcher          = $session.CreateUpdateSearcher()
        $searcher.Online   = $true
        $criteria          = "IsInstalled=0 and IsHidden=0"   # cobre Software e Driver
        $searchResult      = $searcher.Search($criteria)

        $updateCount = [int]$searchResult.Updates.Count
        if ($updateCount -le 0) {
            Write-Log "Nenhuma atualização pendente."
            # Informativo (não é pergunta; remova se quiser 100% silencioso)
            Write-Host "O sistema já está com os patches em dia." -ForegroundColor Green
            Write-Host ""
            return
        }

        Write-Log "Detectadas $updateCount atualizações (WUA/COM)."
        Write-Host "Detectadas $updateCount atualizações." -ForegroundColor Yellow
        Write-Host ""

        # Aceita EULAs silenciosamente
        foreach ($upd in @($searchResult.Updates)) {
            try { if (-not $upd.EulaAccepted) { $upd.AcceptEula() } } catch { }
        }

        # Monta coleção para download
        $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($upd in @($searchResult.Updates)) {
            if (-not $upd.IsDownloaded) { [void]$toDownload.Add($upd) }
        }

        if ($toDownload.Count -gt 0) {
            $downloader          = $session.CreateUpdateDownloader()
            $downloader.Updates  = $toDownload
            $downloadResult      = $downloader.Download()
            Write-Log "Download concluído. ResultCode=$($downloadResult.ResultCode)"
        }

        # Monta coleção para instalação (somente já baixadas)
        $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($upd in @($searchResult.Updates)) {
            if ($upd.IsDownloaded) { [void]$toInstall.Add($upd) }
        }

        if ($toInstall.Count -gt 0) {
            $installer           = $session.CreateUpdateInstaller()
            $installer.ForceQuiet = $true   # 100% silencioso
            $installer.Updates    = $toInstall
            $installResult        = $installer.Install()

            Write-Log "Instalação concluída. ResultCode=$($installResult.ResultCode); RebootRequired=$($installResult.RebootRequired)"

            # Checa reinício necessário (COM e fallback por registro)
            $precisa = $false
            try { if ($installResult.RebootRequired) { $precisa = $true } } catch { $precisa = $false }
            if (-not $precisa) { if (Test-RebootRequired) { $precisa = $true } }

            if ($precisa) {
                $global:NecessitaReiniciar = $true
                Write-Log "AVISO: Sistema requer reinício para concluir patches."
                # Informativo (não é pergunta; remova se quiser 100% silencioso)
                Write-Host "Reinicialização necessária detectada. O sistema reiniciará ao concluir o script." -ForegroundColor Magenta
                Write-Host ""
            }

            Write-Log "Processo de atualização concluído com sucesso (WUA/COM)."
            Write-Host "Processo de atualização concluído com sucesso!" -ForegroundColor Green
            Write-Host ""
        }
        else {
            Write-Log "Nenhuma atualização em estado 'baixado' para instalar."
            Write-Host "Nenhuma atualização disponível para instalação." -ForegroundColor Green
            Write-Host ""
        }
    }
    catch {
        # Sem erro em tela; apenas loga e tenta um fallback opcional e silencioso
        Write-Log "Falha em Invoke-SmartWindowsUpdate (WUA/COM): $($_.Exception.Message)"

        # Fallback silencioso: USOClient (scan/download/install) — sem prompts
        try {
            Write-Log "Fallback via USOClient: StartScan/StartDownload/StartInstall."
            Start-Process -FilePath "usoclient.exe" -ArgumentList "StartScan"     -WindowStyle Hidden -Wait
            Start-Process -FilePath "usoclient.exe" -ArgumentList "StartDownload" -WindowStyle Hidden -Wait
            Start-Process -FilePath "usoclient.exe" -ArgumentList "StartInstall"  -WindowStyle Hidden -Wait

            if (Test-RebootRequired) {
                $global:NecessitaReiniciar = $true
                Write-Log "AVISO: Reinício necessário após USOClient."
            }

            # Informativo; remova se quiser 100% silencioso
            Write-Host "Atualização concluída (fallback USOClient), sem prompts." -ForegroundColor Green
            Write-Host ""
        }
        catch {
            # Último recurso: registra e fica silencioso (sem lançar erro)
            Write-Log "Falha também no fallback USOClient: $($_.Exception.Message)"
        }
    }
}
