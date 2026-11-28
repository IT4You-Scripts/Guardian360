# ============================================
# Função: Optimize-NetworkSettings
# Configura DNS Google em TODOS os adaptadores
# de rede ativos (Ethernet e Wi-Fi)
# Só altera a placa cujo DNS atual for diferente do Google.
# ============================================
function Optimize-NetworkSettings {
    [CmdletBinding()]
    param()

    try {
        $dnsAlvo = @('8.8.8.8', '8.8.4.4')

        # Lê o DNS IPv4 atual da placa (vazio se não for possível ler)
        function Get-DnsAtualDaPlaca {
            param([int]$IfIndex)
            try {
                return @((Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses | Where-Object { $_ })
            } catch {
                return @()
            }
        }

        # Buscar todos os adaptadores físicos ativos (Ethernet e Wi-Fi)
        $adapters = @(Get-NetAdapter | Where-Object {
            $_.Status -eq 'Up' -and
            $_.InterfaceDescription -notmatch 'Virtual|Bluetooth|TAP|VPN|Hyper-V|VMware|VirtualBox'
        })

        if ($adapters.Count -eq 0) {
            throw "Nenhum adaptador de rede ativo encontrado."
        }

        $ajustados  = @()
        $jaCorretos = @()
        $falhas     = @()

        foreach ($adapter in $adapters) {
            $adapterName = $adapter.Name

            try {
                $atual = @(Get-DnsAtualDaPlaca -IfIndex $adapter.ifIndex)

                if (($atual -join ',') -eq ($dnsAlvo -join ',')) {
                    Write-Host "DNS da placa '$adapterName' já está correto (8.8.8.8 / 8.8.4.4). Nada a fazer." -ForegroundColor Green
                    $jaCorretos += $adapterName
                    continue
                }

                Write-Host "Ajustando DNS da placa '$adapterName' ($($adapter.InterfaceDescription))..." -ForegroundColor Cyan

                # Aplica DNS do Google
                netsh interface ip set dns name="$adapterName" source=static address=8.8.8.8 register=primary validate=no | Out-Null
                $codigo1 = $LASTEXITCODE
                netsh interface ip add dns name="$adapterName" addr=8.8.4.4 index=2 validate=no | Out-Null
                $codigo2 = $LASTEXITCODE

                # Confirma lendo novamente (algumas leituras demoram um instante)
                $confirmado = $false
                for ($tentativa = 1; $tentativa -le 3; $tentativa++) {
                    $depois = @(Get-DnsAtualDaPlaca -IfIndex $adapter.ifIndex)
                    if (($depois -join ',') -eq ($dnsAlvo -join ',')) { $confirmado = $true; break }
                    Start-Sleep -Seconds 1
                }

                if ($confirmado) {
                    Write-Host "DNS ajustado para Google (8.8.8.8 / 8.8.4.4) na placa '$adapterName'." -ForegroundColor Green
                    $ajustados += $adapterName
                }
                else {
                    Write-Host "Não foi possível confirmar o DNS na placa '$adapterName' (netsh: $codigo1/$codigo2)." -ForegroundColor Yellow
                    $falhas += "$adapterName (DNS atual: $(if ($depois.Count) { $depois -join ', ' } else { 'indisponível' }))"
                }
            }
            catch {
                Write-Host "Falha ao ajustar DNS da placa '$adapterName': $($_.Exception.Message)" -ForegroundColor Yellow
                $falhas += "$adapterName ($($_.Exception.Message))"
            }
        }

        $partes = @()
        if ($ajustados.Count  -gt 0) { $partes += "ajustado em: $($ajustados -join ', ')" }
        if ($jaCorretos.Count -gt 0) { $partes += "já estava correto em: $($jaCorretos -join ', ')" }
        if ($falhas.Count     -gt 0) { $partes += "falha em: $($falhas -join '; ')" }

        $mensagem = "DNS Google (8.8.8.8 / 8.8.4.4) - $($partes -join ' | ')."
        return $mensagem
    }
    catch {
        Write-Host "Erro ao ajustar DNS: $_" -ForegroundColor Red
        throw
    }
}
