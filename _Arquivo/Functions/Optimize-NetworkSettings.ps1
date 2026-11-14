# ============================================
# Função: Optimize-NetworkSettings
# Configura DNS Google em TODOS os adaptadores
# de rede ativos (Ethernet e Wi-Fi)
# ============================================
function Optimize-NetworkSettings {
    [CmdletBinding()]
    param()

    try {
        # Buscar todos os adaptadores físicos ativos (Ethernet e Wi-Fi)
        $adapters = Get-NetAdapter | Where-Object { 
            $_.Status -eq 'Up' -and 
            $_.InterfaceDescription -notmatch 'Virtual|Bluetooth|TAP|VPN|Hyper-V|VMware|VirtualBox'
        }

        if (-not $adapters -or $adapters.Count -eq 0) {
            throw "Nenhum adaptador de rede ativo encontrado."
        }

        $resultados = @()

        foreach ($adapter in $adapters) {
            $adapterName = $adapter.Name
            Write-Host "Ajustando DNS da placa '$adapterName' ($($adapter.InterfaceDescription))..." -ForegroundColor Cyan

            # Aplica DNS do Google
            netsh interface ip set dns name="$adapterName" source=static address=8.8.8.8 register=primary validate=no | Out-Null
            netsh interface ip add dns name="$adapterName" addr=8.8.4.4 index=2 validate=no | Out-Null

            Write-Host "DNS ajustado para Google (8.8.8.8 / 8.8.4.4) na placa '$adapterName'." -ForegroundColor Green
            $resultados += "$adapterName"
        }

        $mensagem = "DNS configurado como Google (8.8.8.8 / 8.8.4.4) para: $($resultados -join ', ')."
        return $mensagem
    }
    catch {
        Write-Host "Erro ao ajustar DNS: $_" -ForegroundColor Red
        throw
    }
}