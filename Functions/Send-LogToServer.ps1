function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,     # IP ou Hostname
        [switch]$Simulado
    )

    # Diretório local de logs
    $agora = Get-Date
    $ano   = $agora.Year
    $mes   = $agora.Month
    $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
    $mesNomeFormatado = (Get-Culture).TextInfo.ToTitleCase($mesNome)
    $mesFormatado = "{0:D2}. {1}" -f $mes, $mesNomeFormatado
    $diretorioLogLocal = "C:\Guardian\Logs\$ano\$mesFormatado"

    # Seleciona o .log mais recente
    $arquivoMaisRecente = Get-ChildItem -Path $diretorioLogLocal -File -Filter '*.log' -ErrorAction SilentlyContinue |
                          Sort-Object LastWriteTime -Descending |
                          Select-Object -First 1

    if (-not $arquivoMaisRecente) {
        $msg = "Nenhum arquivo .log encontrado em: $diretorioLogLocal"
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # Caminhos remotos
    $servidorHost    = $Server
    $servidorBase    = "\\$servidorHost\TI"
    $destinoServidor = "$servidorBase\$ano\$mesFormatado"
    $nomeFinalLog    = "$($env:COMPUTERNAME).log"

    Write-Host "Centralizando log no servidor (modo blindado)..." -ForegroundColor Cyan

    # Teste rápido de rede (evita travamento)
    try {
        if (-not (Test-Connection -ComputerName $servidorHost -Count 1 -Quiet -TimeoutSeconds 1)) {
            throw "Servidor inacessível"
        }
    } catch {
        $msg = "[ALERTA] Servidor de Arquivos '$servidorHost' não respondeu ao ping."
        Show-PrettyWarning $msg
        Send-LogAlert $msg
        return
    }

    # Simulação
    if ($Simulado) {
        $msg = "SIMULAÇÃO: Robocopy '$($arquivoMaisRecente.FullName)' -> '$destinoServidor\$nomeFinalLog'"
        Write-Host $msg -ForegroundColor Cyan
        Send-LogAlert $msg
        return
    }

    # Comando Robocopy (à prova de travamento SMB)
    $argumentos = @(
        "`"$($arquivoMaisRecente.Directory.FullName)`"",
        "`"$destinoServidor`"",
        "`"$($arquivoMaisRecente.Name)`"",
        "/R:1",     # 1 retry
        "/W:1",     # espera 1s
        "/NFL",     # sem lista de arquivos
        "/NDL",     # sem lista de diretórios
        "/NJH",     # sem header
        "/NJS",     # sem summary
        "/NC",      # sem classe
        "/NS"       # sem tamanho
    ) -join ' '

    try {
        $process = Start-Process `
            -FilePath "robocopy.exe" `
            -ArgumentList $argumentos `
            -Wait `
            -NoNewWindow `
            -PassThru

        # ExitCode < 8 = sucesso no Robocopy
        if ($process.ExitCode -ge 8) {
            throw "Robocopy falhou (ExitCode $($process.ExitCode))"
        }

        $okMsg = "Log '$($arquivoMaisRecente.Name)' enviado com sucesso para '$destinoServidor'."
        Write-Host $okMsg -ForegroundColor Green
        Send-LogAlert $okMsg

    } catch {
        $errMsg = "Erro ao enviar log via Robocopy: $($_.Exception.Message)"
        Write-Host $errMsg -ForegroundColor Red
        Send-LogAlert $errMsg
        return
    }
}

