# ============================================
# Função: Optimize-PowerSettings
# ============================================
function Optimize-PowerSettings {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Otimizando configurações de energia..." -ForegroundColor Cyan

        $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

        # GUID em qualquer idioma do Windows (a linha do powercfg muda: "Power Scheme GUID:",
        # "GUID do Esquema de Energia:" etc.), por isso extraímos pelo formato do GUID.
        $padraoGuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

        function Get-PlanoAtivoGuid {
            $saida = (powercfg /getactivescheme | Out-String)
            $achado = [regex]::Match($saida, $padraoGuid)
            if ($achado.Success) { return $achado.Value.ToLowerInvariant() }
            return $null
        }

        # Executa o powercfg e informa se terminou sem erro (sem vazar saída para o retorno)
        function Invoke-PowercfgChecked {
            param([string[]]$Argumentos)
            & powercfg @Argumentos 2>&1 | Out-Null
            return ($LASTEXITCODE -eq 0)
        }

        $avisos = @()

        # Garante e ativa o plano High Performance somente se ele ainda não estiver ativo
        $ativo = Get-PlanoAtivoGuid
        if ($ativo -ne $highPerfGuid) {
            $listaPlanos = (powercfg /list | Out-String)
            if ($listaPlanos -notmatch [regex]::Escape($highPerfGuid)) {
                # Cria o plano já com o GUID esperado (sem GUID de destino, o Windows
                # geraria um GUID novo a cada execução e o plano abaixo nunca seria ativado).
                [void](Invoke-PowercfgChecked @('/duplicatescheme', 'SCHEME_MIN', $highPerfGuid))
            }

            [void](Invoke-PowercfgChecked @('/setactive', $highPerfGuid))
            $ativo = Get-PlanoAtivoGuid
        }

        # Recupera o plano ativo
        if (-not $ativo) { throw "Falha ao identificar plano ativo." }

        if ($ativo -ne $highPerfGuid) {
            $avisos += "plano High Performance não ficou ativo (plano ativo: $ativo)"
        }

        # Verifica se há bateria
        $hasBattery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue

        $falhasAjuste = @()

        # USB Selective Suspend (AC)
        if (-not (Invoke-PowercfgChecked @('/setacvalueindex', $ativo,
                '2a737441-1930-4402-8d77-b2bebba308a3',
                '48983702-45ee-4273-9aa2-d11f35229dc5', '0'))) {
            $falhasAjuste += 'USB Selective Suspend (AC)'
        }

        # USB Selective Suspend (DC se houver bateria)
        if ($hasBattery) {
            if (-not (Invoke-PowercfgChecked @('/setdcvalueindex', $ativo,
                    '2a737441-1930-4402-8d77-b2bebba308a3',
                    '48983702-45ee-4273-9aa2-d11f35229dc5', '0'))) {
                $falhasAjuste += 'USB Selective Suspend (DC)'
            }
        }

        # Timeouts AC
        foreach ($ajuste in @(
            @('monitor-timeout-ac', '15'),
            @('disk-timeout-ac',    '0'),
            @('standby-timeout-ac', '0')
        )) {
            if (-not (Invoke-PowercfgChecked @('/change', $ajuste[0], $ajuste[1]))) { $falhasAjuste += $ajuste[0] }
        }

        # Timeouts DC (se houver)
        if ($hasBattery) {
            foreach ($ajuste in @(
                @('monitor-timeout-dc', '10'),
                @('disk-timeout-dc',    '15'),
                @('standby-timeout-dc', '20')
            )) {
                if (-not (Invoke-PowercfgChecked @('/change', $ajuste[0], $ajuste[1]))) { $falhasAjuste += $ajuste[0] }
            }
        }

        # Reaplica o plano ativo para que os valores gravados tenham efeito imediato
        [void](Invoke-PowercfgChecked @('/setactive', $ativo))

        if ($falhasAjuste.Count -gt 0) {
            $avisos += "ajustes não aplicados: $($falhasAjuste -join ', ')"
        }

        if ($avisos.Count -gt 0) {
            Write-Host "Configurações de energia aplicadas com ressalvas." -ForegroundColor Yellow
            return "Configurações de energia aplicadas com ressalvas: $($avisos -join ' | ')"
        }

        Write-Host "Configurações de energia otimizadas." -ForegroundColor Green

        return "Configurações de energia otimizadas (High Performance + ajustes AC/DC)."
    }
    catch {
        Write-Host "Não foi possível otimizar as configurações de energia." -ForegroundColor Red
        throw
    }
}
