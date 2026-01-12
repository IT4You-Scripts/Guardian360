# Checa estado da bateria (apenas notebooks)
function Test-BatteryHealth {
    # Lista de tipos de chassi considerados laptops/portáteis
    # 8: Portable, 9: Laptop, 10: Notebook, 11: Handheld, 12: Docking Station, 14: Sub Notebook
    $laptopChassisTypes = @(8, 9, 10, 11, 12, 14)
    $chassis = Get-CimInstance -ClassName Win32_SystemEnclosure
    $isLaptop = $false

    foreach ($type in $chassis.ChassisTypes) {
        if ($laptopChassisTypes -contains $type) { $isLaptop = $true }
    }

    # Verifica se existe uma bateria presente no sistema
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

    if ($isLaptop -and $battery) {
        Write-Host "----------------------------------------------------------------"
        Write-Host "Verificando saúde da bateria (Dispositivo Portátil Detectado)..." -ForegroundColor Cyan
        Write-Host ""
		Write-Log "Verificando saúde da bateria (Dispositivo Portátil Detectado)...." 
		Write-Log "" 
			
        try {
            # Obtém dados de capacidade via WMI (Namespace root/wmi)
            $fullCharge = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop
            $staticData = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop

            $designCap  = $staticData.DesignedCapacity
            $currentCap = $fullCharge.FullChargedCapacity

            if ($designCap -gt 0) {
                $health = [Math]::Round(($currentCap / $designCap) * 100, 1)

                # Define a cor baseada no desgaste
                $color = "Green"
                if ($health -lt 50) { $color = "Red" }
                elseif ($health -lt 80) { $color = "Yellow" }

                Write-Host "Saúde da Bateria: $health%" -ForegroundColor $color
                Write-Host "Capacidade de Fábrica: $designCap mWh" -ForegroundColor Gray
                Write-Host "Capacidade Máxima Atual: $currentCap mWh" -ForegroundColor Gray
				Write-Log "Saúde da Bateria: $health%"
                Write-Log "Capacidade de Fábrica: $designCap mWh" 
                Write-Log "Capacidade Máxima Atual: $currentCap mWh" 
				

                # Alerta proativo de troca
                if ($health -lt 60) {
                    Write-Host ""
                    Write-Host "!!! ATENÇÃO: Bateria com alto nível de desgaste. Recomenda-se substituição !!!" -ForegroundColor Red
                }

                Write-Log "Saúde da Bateria: $health% (Design: $designCap mWh | Atual: $currentCap mWh)"
            }
        }
        catch {
            Write-Host "Aviso: Hardware de bateria detectado, mas não foi possível ler os dados de mWh." -ForegroundColor Yellow
            Write-Log "Não foi possível extrair dados detalhados da bateria (BatteryFullChargedCapacity)."
        }
        
        Write-Host ""
        Write-Host "----------------------------------------------------------------"
        Write-Host ""
    }
}
