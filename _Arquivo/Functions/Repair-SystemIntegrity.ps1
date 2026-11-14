function Repair-SystemIntegrity {
    [CmdletBinding()]
    param(
        [string]$SourcePath
    )

    function Test-PendingReboot {
        try {
            $cbs  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootPending' -ErrorAction SilentlyContinue
            $wu   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'RebootRequired' -ErrorAction SilentlyContinue
            $pfr  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
            $pxml = Test-Path "$env:windir\winsxs\pending.xml"
            return ($cbs -or $wu -or $pfr -or $pxml)
        } catch {
            Write-Log "ALERTA: Falha ao verificar reinicialização pendente: $($_.Exception.Message)"
            return $false
        }
    }

    try {
        $pendingBefore = Test-PendingReboot
        if ($pendingBefore) {
            Write-Log "ALERTA: Reinicialização pendente detectada ANTES da manutenção."
        }

        $cleanupArgs = "/Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart"
        $cleanupProc = Start-Process dism.exe -ArgumentList $cleanupArgs -Wait -PassThru -NoNewWindow
        $cleanupExit = $cleanupProc.ExitCode

        if ($cleanupExit -ne 0 -and $cleanupExit -ne 3010) {
            Write-Log "ERRO: StartComponentCleanup falhou (ExitCode=$cleanupExit)."
        }

        $dismArgs = "/Online /Cleanup-Image /RestoreHealth"
        if ($SourcePath) {
            $dismArgs += " /Source:`"$SourcePath`" /LimitAccess"
        }

        $dismProc = Start-Process dism.exe -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow
        $dismExit = $dismProc.ExitCode

        if ($dismExit -eq 3010) {
            Write-Log "ALERTA: DISM concluiu com sucesso, mas requer reinicialização (3010)."
        } elseif ($dismExit -ne 0) {
            Write-Log "ERRO: DISM RestoreHealth falhou (ExitCode=$dismExit)."
        }

        $sfcProc = Start-Process sfc.exe -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
        $sfcExit = $sfcProc.ExitCode

        switch ($sfcExit) {
            1 { Write-Log "ALERTA: SFC encontrou e reparou corrupção de arquivos." }
            2 { Write-Log "ERRO: SFC encontrou corrupção que NÃO pôde ser reparada." }
            3 { Write-Log "ERRO: SFC não conseguiu executar a verificação." }
            Default {
                if ($sfcExit -ne 0) {
                    Write-Log "ALERTA: SFC retornou código inesperado ($sfcExit)."
                }
            }
        }

        if ($sfcExit -ne 0) {
            $cbsPath = "$env:windir\Logs\CBS\CBS.log"
            if (Test-Path $cbsPath) {

                $srCannot = Select-String -Path $cbsPath -Pattern '\[SR\].*Cannot repair' -ErrorAction SilentlyContinue
                $qtdCannot = ($srCannot | Measure-Object).Count

                $srRepaired = Select-String -Path $cbsPath -Pattern '\[SR\].*Repairing corrupted' -ErrorAction SilentlyContinue
                $qtdRepaired = ($srRepaired | Measure-Object).Count

                if ($qtdCannot -gt 0) {
                    Write-Log "ERRO: SFC - itens não reparados: $qtdCannot."
                } elseif ($qtdRepaired -gt 0 -and $sfcExit -eq 1) {
                    Write-Log "ALERTA: SFC - itens reparados: $qtdRepaired."
                }
            } else {
                Write-Log "ALERTA: CBS.log não encontrado para sumarizar resultados do SFC."
            }
        }

        $pendingAfter = Test-PendingReboot
        if ($pendingAfter -or $dismExit -eq 3010 -or $cleanupExit -eq 3010) {
            Write-Log "ALERTA: Reinicialização recomendada após a manutenção."
        }

        $msg = "SFC/DISM finalizados. ExitCodes: SFC=$sfcExit, DISM=$dismExit, Cleanup=$cleanupExit. PendingBefore=$pendingBefore, PendingAfter=$pendingAfter"

        return [PSCustomObject]@{
            MensagemTecnica          = $msg
            PendingRebootBefore      = $pendingBefore
            ComponentCleanupExitCode = $cleanupExit
            DismExitCode             = $dismExit
            SfcExitCode              = $sfcExit
            PendingRebootAfter       = $pendingAfter
        }
    }
    catch {
        Write-Log "ERRO: Falha durante a manutenção preventiva: $($_.Exception.Message)"
        throw
    }
}
