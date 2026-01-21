function Optimize-NetworkSettings {
    Write-Host "Ajustando DNS da placa 'Ethernet'..." -ForegroundColor Cyan

    try {
        # Nome da placa real
        $adapterName = "Ethernet"

        # Aplica DNS do Google
        netsh interface ip set dns name="$adapterName" source=static address=8.8.8.8 register=primary validate=no | Out-Null
        netsh interface ip add dns name="$adapterName" addr=8.8.4.4 index=2 validate=no | Out-Null

        Write-Host "DNS ajustado para Google (8.8.8.8 / 8.8.4.4) na placa '$adapterName'." -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao ajustar DNS: $_" -ForegroundColor Red
    }
}
