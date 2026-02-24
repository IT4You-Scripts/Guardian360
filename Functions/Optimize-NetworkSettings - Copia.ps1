# ============================================
# Função: Optimize-NetworkSettings
# ============================================
function Optimize-NetworkSettings {
    [CmdletBinding()]
    param()

    try {
        $adapterName = "Ethernet"
        Write-Host "Ajustando DNS da placa '$adapterName'..." -ForegroundColor Cyan

        # Checa se adaptador existe
        $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        if (-not $adapter) { throw "Adaptador '$adapterName' não encontrado." }

        # Aplica DNS do Google
        netsh interface ip set dns name="$adapterName" source=static address=8.8.8.8 register=primary validate=no | Out-Null
        netsh interface ip add dns name="$adapterName" addr=8.8.4.4 index=2 validate=no | Out-Null

        Write-Host "DNS ajustado para Google (8.8.8.8 / 8.8.4.4) na placa '$adapterName'." -ForegroundColor Green

        return "DNS configurado como Google (8.8.8.8 / 8.8.4.4) para o adaptador $adapterName."
    }
    catch {
        Write-Host "Erro ao ajustar DNS: $_" -ForegroundColor Red
        throw
    }
}
