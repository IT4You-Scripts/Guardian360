# Verifica e repara os arquivos e o registro do sistema operacional: SFC e DISM
function Repair-SystemIntegrity {
    [CmdletBinding()]
    param(
        [string]$SourcePath
    )

    # Observação: este script já roda elevado e já existe Write-Log($mensagem) no escopo,
    # escrevendo em $arquivoLog. Aqui usamos SOMENTE Write-Log e registramos APENAS alertas.

    function Test-PendingReboot {
        try {
            $cbs = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootPending' -ErrorAction SilentlyContinue
            $wu  = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'RebootRequired' -ErrorAction SilentlyContinue
            $pfr = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
            $pxml = Test-Path "$env:windir\winsxs\pending.xml"
            return ($cbs -or $wu -or $pfr -or $pxml)
        } catch {
            Write-Log "ALERTA: Falha ao verificar reinicialização pendente: $($_.Exception.Message)"
            return $false
        }
    }

    try {
        # 1) Sinaliza se já havia reinício pendente (somente alerta, sem prompts)
        $pendingBefore = Test-PendingReboot
        if ($pendingBefore) {
            Write-Log "ALERTA: Reinicialização pendente detectada ANTES da manutenção."
        }

        # 2) Limpeza de componentes (DISM) - silenciosa
        $cleanupArgs = "/Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart"
        $cleanupProc = Start-Process -FilePath "dism.exe" -ArgumentList $cleanupArgs -Wait -PassThru -NoNewWindow
        $cleanupExit = $cleanupProc.ExitCode
        if ($cleanupExit -ne 0 -and $cleanupExit -ne 3010) {
            Write-Log "ERRO: StartComponentCleanup falhou (ExitCode=$cleanupExit)."
        }

        # 3) DISM RestoreHealth (com fonte offline, se fornecida)
        $dismArgs = "/Online /Cleanup-Image /RestoreHealth"
        if ($SourcePath) {
            # Ex.: 'WIM:D:\sources\install.wim:1' ou 'D:\sources\sxs'
            $dismArgs += " /Source:`"$SourcePath`" /LimitAccess"
        }
        $dismProc = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow
        $dismExit = $dismProc.ExitCode
        if ($dismExit -eq 3010) {
            Write-Log "ALERTA: DISM concluiu com sucesso, mas requer reinicialização (3010)."
        } elseif ($dismExit -ne 0) {
            Write-Log "ERRO: DISM RestoreHealth falhou (ExitCode=$dismExit). Verifique C:\Windows\Logs\DISM\dism.log."
        }

        # 4) SFC /scannow (captura de códigos e ALERTAS)
        $sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
        $sfcExit = $sfcProc.ExitCode

        # Mapeamento de alertas mínimos (somente quando há algo a observar)
        switch ($sfcExit) {
            0 { # OK - não registrar nada (somente alertas)
            }
            1 {
                Write-Log "ALERTA: SFC encontrou e reparou corrupção de arquivos."
            }
            2 {
                Write-Log "ERRO: SFC encontrou corrupção que NÃO pôde ser reparada."
            }
            3 {
                Write-Log "ERRO: SFC não conseguiu executar a verificação."
            }
            Default {
                Write-Log "ALERTA: SFC retornou código inesperado ($sfcExit)."
            }
        }

        # 5) CBS.log — registrar APENAS contagens resumidas (sem arquivo extra)
        #    Só busca detalhes quando SFC sinalizou algo (exit != 0)
        if ($sfcExit -ne 0) {
            $cbsPath = "$env:windir\Logs\CBS\CBS.log"
            if (Test-Path $cbsPath) {
                # Contagem de itens não reparados (alerta crítico)
                $srCannot = Select-String -Path $cbsPath -Pattern '\[SR\].*Cannot repair' -ErrorAction SilentlyContinue
                $qtdCannot = ($srCannot | Measure-Object).Count

                # Contagem de itens reparados (alerta informativo)
                $srRepaired = Select-String -Path $cbsPath -Pattern '\[SR\].*Repairing corrupted' -ErrorAction SilentlyContinue
                $qtdRepaired = ($srRepaired | Measure-Object).Count

                if ($qtdCannot -gt 0) {
                    Write-Log "ERRO: SFC - itens não reparados: $qtdCannot. Consulte $cbsPath (linhas [SR])."
                } elseif ($qtdRepaired -gt 0 -and $sfcExit -eq 1) {
                    Write-Log "ALERTA: SFC - itens reparados: $qtdRepaired."
                }
            } else {
                Write-Log "ALERTA: CBS.log não encontrado para sumarizar resultados do SFC."
            }
        }

        # 6) Reboot pendente após manutenção (recomenda, não reinicia automaticamente)
        $pendingAfter = Test-PendingReboot
        if ($pendingAfter -or $dismExit -eq 3010 -or $cleanupExit -eq 3010) {
            Write-Log "ALERTA: Reinicialização recomendada após a manutenção."
        }

        # Retorno simples (caso o chamador queira telemetria)
        return [PSCustomObject]@{
            PendingRebootBefore = $pendingBefore
            ComponentCleanupExitCode = $cleanupExit
            DismExitCode = $dismExit
            SfcExitCode = $sfcExit
            PendingRebootAfter = $pendingAfter
        }
    }
    catch {
        Write-Log "ERRO: Falha durante a manutenção preventiva: $($_.Exception.Message)"
        throw
    }
}
