# Otimiza as Configurações de Energia 
function Optimize-PowerSettings {
    Write-Host "Otimizando as configurações de energia para Máxima Performance..." -ForegroundColor Cyan
    Write-Host ""

    try {
        # 1. Tenta ativar o plano de "Alto Desempenho" (High Performance)
        # GUID padrão do Windows para Alto Desempenho: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        powercfg /setactive $highPerfGuid 2>$null

        # 2. Desabilitar suspensão seletiva USB (evita que periféricos desliguem sozinhos)
        powercfg /setacvalueindex $highPerfGuid 2a737441-1930-4402-8d77-b2bebba308a3 48983702-45ee-4273-9aa2-d11f35229dc5 0
        
        # 3. Aplicar os tempos limites (usando o esquema atual ativo)
        $timeouts = @(
            "monitor-timeout-ac 15", "monitor-timeout-dc 10",
            "disk-timeout-ac 0",    "disk-timeout-dc 15",
            "standby-timeout-ac 0", "standby-timeout-dc 20",
            "hibernate-timeout-ac 0", "hibernate-timeout-dc 30"
        )

        foreach ($t in $timeouts) {
            Invoke-Expression "powercfg /change $t"
        }

        # 4. Desabilitar a inicialização rápida (Fast Startup) 
        # Frequentemente causa bugs de drivers e impede que o sistema limpe a RAM no "Desligar"
        powercfg /h off

        Write-Host ""
        Write-Host "Configurações de energia otimizadas com Sucesso!" -ForegroundColor Green
        Write-Host ""
        Write-Log ""
        Write-Log "Configurações de energia otimizadas (Alto Desempenho e FastBoot OFF)."
        Write-Log ""
    }
    catch {
        Write-Host "Erro ao ajustar configurações de energia: $_" -ForegroundColor Red
        Write-Host ""
        Write-Log "Erro nas configurações de energia: $_"
        Write-Log ""
    }
}
