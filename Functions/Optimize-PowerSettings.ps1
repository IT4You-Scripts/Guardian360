function Optimize-PowerSettings {
    Write-Host "Otimizando configurações de energia..." -ForegroundColor Cyan

    try {
        $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

        if (-not (powercfg /list | Select-String $highPerfGuid)) {
            powercfg /duplicatescheme SCHEME_MIN | Out-Null
        }

        powercfg /setactive $highPerfGuid | Out-Null

        $activeScheme = (powercfg /getactivescheme) -replace '.*GUID:\s*([a-f0-9\-]+).*', '$1'
        if (-not $activeScheme) { throw }

        $hasBattery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue

        # USB Selective Suspend (erro suprimido por compatibilidade)
        powercfg /setacvalueindex $activeScheme `
            2a737441-1930-4402-8d77-b2bebba308a3 `
            48983702-45ee-4273-9aa2-d11f35229dc5 0 2>$null

        if ($hasBattery) {
            powercfg /setdcvalueindex $activeScheme `
                2a737441-1930-4402-8d77-b2bebba308a3 `
                48983702-45ee-4273-9aa2-d11f35229dc5 0 2>$null
        }

        # Timeouts seguros
        powercfg /change monitor-timeout-ac 15 | Out-Null
        powercfg /change disk-timeout-ac 0     | Out-Null
        powercfg /change standby-timeout-ac 0  | Out-Null

        if ($hasBattery) {
            powercfg /change monitor-timeout-dc 10 | Out-Null
            powercfg /change disk-timeout-dc 15    | Out-Null
            powercfg /change standby-timeout-dc 20 | Out-Null
        }

        powercfg /h off | Out-Null

        Write-Host "Configurações de energia otimizadas." -ForegroundColor Green
        Write-Log "Energia otimizada (High Performance, USB suspend OFF, hibernação OFF)."
    }
    catch {
        Write-Host "Não foi possível otimizar as configurações de energia." -ForegroundColor Red
        Write-Log "Erro nas configurações de energia."
    }
}
