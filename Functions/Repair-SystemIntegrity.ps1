function Repair-SystemIntegrity {
    [CmdletBinding()]
    param(
        [string]$SourcePath
    )

    # Tempo maximo (minutos) de cada etapa demorada: DISM cleanup, DISM RestoreHealth e SFC.
    $tempoLimiteMin = 60

    function Test-PendingReboot {
        try {
            # RebootPending e RebootRequired sao SUBCHAVES (nao valores): usar Test-Path.
            $cbs  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            $wu   = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            $pfr  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
            $pxml = Test-Path "$env:windir\winsxs\pending.xml"
            return [bool]($cbs -or $wu -or $pfr -or $pxml)
        } catch {
            return $false
        }
    }

    # Executa um programa e espera ate o tempo limite. Se estourar, encerra o programa
    # e seus processos filhos e devolve ExitCode = -1 com TimedOut = $true.
    function Invoke-ProcessWithTimeout {
        param(
            [string]$FilePath,
            [string]$Arguments,
            [int]$TimeoutMinutes
        )

        $proc = Start-Process $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow
        $null = $proc.Handle   # garante a leitura do ExitCode depois que o processo terminar

        if ($proc.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            return [PSCustomObject]@{ ExitCode = [int]$proc.ExitCode; TimedOut = $false }
        }

        try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch {}
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}

        return [PSCustomObject]@{ ExitCode = -1; TimedOut = $true }
    }

    try {
        $pendingBefore = Test-PendingReboot
        $estouraramTempo = @()

        $cleanupArgs = "/Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart"
        $cleanupRes  = Invoke-ProcessWithTimeout -FilePath 'dism.exe' -Arguments $cleanupArgs -TimeoutMinutes $tempoLimiteMin
        $cleanupExit = $cleanupRes.ExitCode
        if ($cleanupRes.TimedOut) { $estouraramTempo += 'DISM-StartComponentCleanup' }

        $dismArgs = "/Online /Cleanup-Image /RestoreHealth"
        if ($SourcePath) {
            $dismArgs += " /Source:`"$SourcePath`" /LimitAccess"
        }

        $dismRes  = Invoke-ProcessWithTimeout -FilePath 'dism.exe' -Arguments $dismArgs -TimeoutMinutes $tempoLimiteMin
        $dismExit = $dismRes.ExitCode
        if ($dismRes.TimedOut) { $estouraramTempo += 'DISM-RestoreHealth' }

        $sfcRes  = Invoke-ProcessWithTimeout -FilePath 'sfc.exe' -Arguments '/scannow' -TimeoutMinutes $tempoLimiteMin
        $sfcExit = $sfcRes.ExitCode
        if ($sfcRes.TimedOut) { $estouraramTempo += 'SFC' }

        $pendingAfter = Test-PendingReboot

        $msg = "SFC/DISM finalizados. ExitCodes: SFC=$sfcExit, DISM=$dismExit, Cleanup=$cleanupExit. PendingBefore=$pendingBefore, PendingAfter=$pendingAfter"
        if ($estouraramTempo.Count -gt 0) {
            $msg += ". TempoLimiteExcedido=$($estouraramTempo -join '+') (ExitCode -1)"
        }

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
        throw
    }
}
