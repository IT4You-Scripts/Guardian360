# Otimiza as Configurações de Rede (apenas DNS)
function Optimize-NetworkSettings {
    Write-Host "Otimizando rede e aplicando DNS via Índice de Interface..." -ForegroundColor Cyan
    Write-Host ""

    try {
        $mainEthernet = $null

        # 1. Tenta identificar o adaptador físico principal
        try {
            $mainEthernet = Get-NetAdapter -Physical -ErrorAction Stop | 
                Where-Object { $_.Status -eq "Up" -and $_.MediaType -match "802.3" } | 
                Sort-Object Speed -Descending | 
                Select-Object -First 1
        }
        catch {
            # Fallback para WMI clássico se a classe moderna estiver corrompida
            $mainEthernet = Get-CimInstance -Class Win32_NetworkAdapter -Filter "PhysicalAdapter = True AND NetConnectionStatus = 2" -ErrorAction SilentlyContinue |
                Where-Object { $_.AdapterTypeId -eq 0 -or $_.Name -match "Ethernet|Gigabit|Realtek|Intel" } |
                Select-Object -First 1
        }

        if ($null -ne $mainEthernet) {
            # Captura o Índice de forma segura para o Netsh
            $idx = if ($null -ne $mainEthernet.ifIndex) { $mainEthernet.ifIndex } else { $mainEthernet.InterfaceIndex }
            
            if ($null -eq $idx) { throw "Não foi possível capturar o índice da interface." }

            Write-Host "Adaptador detectado: $($mainEthernet.Name) (Índice: $idx)" -ForegroundColor Gray

            # 2. Configuração de DNS usando o ÍNDICE (Elimina erro de sintaxe de nome)
            $isDomainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
            if (-not $isDomainJoined) {
                Write-Host "Aplicando DNS do Google (8.8.8.8)..."
                
                # Usamos o índice diretamente no netsh para evitar erros de caracteres no nome
                netsh interface ip set dns name=$idx source=static address=8.8.8.8 register=primary validate=no
                netsh interface ip add dns name=$idx addr=8.8.4.4 index=2 validate=no
                Write-Host "DNS configurado com sucesso." -ForegroundColor Green
            } else {
                Write-Host "Domínio detectado. DNS preservado." -ForegroundColor Yellow
            }

            # 3. Otimizações de TCP/IP (Afeta o sistema globalmente)
            $templates = @("Internet", "InternetCustom")
            foreach ($tpl in $templates) {
                if (Get-NetTCPSetting -SettingName $tpl -ErrorAction SilentlyContinue) {
                    Set-NetTCPSetting -SettingName $tpl `
                        -AutoTuningLevelLocal Normal `
                        -EcnCapability Enabled `
                        -Timestamps Disabled `
                        -InitialRto 2000 `
                        -MinRto 300 `
                        -MaxSynRetransmissions 2 `
                        -ErrorAction SilentlyContinue
                }
            }

            Clear-DnsClientCache
            Write-Host "As configurações de rede foram otimizadas!" -ForegroundColor Green
            Write-Log ""
            Write-Log "Rede otimizada no adaptador índice $idx ($($mainEthernet.Name))."
        } else {
            Write-Host "Nenhum adaptador Ethernet ativo encontrado." -ForegroundColor Yellow
        }
    }
    catch {
        $msgErro = "ERRO ao otimizar rede: $_"
        Write-Host $msgErro -ForegroundColor Red
        Write-Log $msgErro
    }
}
