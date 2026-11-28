function Clear-WindowsUpdateCache {
    [CmdletBinding()]
    param()

    try {
        # Verifica se está executando como Administrador
        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Host "Execute este script como Administrador para reset completo do Windows Update." -ForegroundColor Yellow
            return "Erro técnico: execução requer privilégios de Administrador."
        }

        Write-Host "Iniciando reset do Windows Update..." -ForegroundColor Cyan

        # --- Proteção: não resetar durante uma atualização em andamento ou reinicialização pendente ---
        $motivoAdiar = @()
        if (Get-Process -Name "TiWorker" -ErrorAction SilentlyContinue) {
            $motivoAdiar += "instalação de atualização em andamento (TiWorker)"
        }
        if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
            $motivoAdiar += "reinicialização pendente (servicing)"
        }
        if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            $motivoAdiar += "reinicialização pendente (Windows Update)"
        }
        if ($motivoAdiar.Count -gt 0) {
            Write-Host "Reset do Windows Update adiado: $($motivoAdiar -join '; ')." -ForegroundColor Yellow
            return "Reset do Windows Update adiado (nada foi alterado): $($motivoAdiar -join '; ')."
        }

        # Ordem de parada e de religação (cryptSvc e bits antes do wuauserv)
        $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
        $folders  = @("$env:systemroot\SoftwareDistribution", "$env:systemroot\System32\catroot2")

        $pendencias = @()

        # Guarda quais serviços estavam em execução para religar somente esses
        $estavamRodando = @()
        foreach ($service in $services) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne 'Stopped') { $estavamRodando += $service }
        }

        # --- Phase 1: Parar serviços ---
        Write-Host "Parando serviços do Windows Update..." -ForegroundColor Yellow
        $naoPararam = @()
        foreach ($service in $services) {
            if (-not (Get-Service -Name $service -ErrorAction SilentlyContinue)) { continue }

            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $timeout = 30

            while ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne 'Stopped' -and $timeout -gt 0) {
                Start-Sleep -Seconds 1
                $timeout--
            }

            if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne 'Stopped') {
                $naoPararam += $service
            }
        }

        # wuauserv e cryptSvc seguram SoftwareDistribution e catroot2: sem eles parados, não apaga
        $criticosAtivos = @($naoPararam | Where-Object { $_ -in @("wuauserv", "cryptSvc") })

        if ($naoPararam.Count -eq 0) {
            Write-Host "Serviços parados." -ForegroundColor Green
        }
        else {
            Write-Host "Serviços que não pararam: $($naoPararam -join ', ')" -ForegroundColor Yellow
            $pendencias += "serviços que não pararam: $($naoPararam -join ', ')"
        }

        # --- Phase 2: Limpar pastas ---
        if ($criticosAtivos.Count -gt 0) {
            Write-Host "Limpeza do cache ignorada: serviço crítico não parou." -ForegroundColor Yellow
            $pendencias += "cache NÃO foi limpo (serviço crítico em execução)"
        }
        else {
            Write-Host "Limpando cache..." -ForegroundColor Yellow
            foreach ($folder in $folders) {
                try {
                    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }

                    $acl = Get-Acl $folder
                    $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544"))
                    Set-Acl $folder $acl -ErrorAction SilentlyContinue

                    Remove-Item "$folder\*" -Recurse -Force -ErrorAction SilentlyContinue

                    $sobraram = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue).Count
                    if ($sobraram -gt 0) {
                        $pendencias += "$sobraram item(ns) não removido(s) em $folder"
                    }
                }
                catch {
                    $pendencias += "falha ao limpar ${folder}: $($_.Exception.Message)"
                }
            }
            Write-Host "Cache limpo." -ForegroundColor Green
        }

        # --- Phase 3: Reiniciar serviços (somente os que estavam em execução) ---
        Write-Host "Reiniciando serviços..." -ForegroundColor Yellow
        $naoVoltaram = @()
        foreach ($service in $services) {
            if ($service -notin $estavamRodando) { continue }

            Start-Service -Name $service -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            if ((Get-Service -Name $service -ErrorAction SilentlyContinue).Status -ne 'Running') {
                $naoVoltaram += $service
            }
        }
        if ($naoVoltaram.Count -gt 0) {
            Write-Host "Serviços que não voltaram: $($naoVoltaram -join ', ')" -ForegroundColor Yellow
            $pendencias += "serviços que não voltaram a executar: $($naoVoltaram -join ', ')"
        }
        else {
            Write-Host "Serviços reiniciados." -ForegroundColor Green
        }

        if ($pendencias.Count -gt 0) {
            Write-Host "Reset do Windows Update concluído com ressalvas." -ForegroundColor Yellow
            return "Reset do Windows Update concluído com ressalvas: $($pendencias -join ' | ')"
        }

        Write-Host "Reset do Windows Update concluído!" -ForegroundColor Cyan

        return "Reset do Windows Update concluído tecnicamente com sucesso."
    }
    catch {
        Write-Host "Falha no reset do Windows Update." -ForegroundColor Red

        $erroDetalhado = ($_ | Format-List * -Force | Out-String).Trim()
        throw "Erro crítico durante Clear-WindowsUpdateCache: $erroDetalhado"
    }
}
