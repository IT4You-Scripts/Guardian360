unction Send-LogToServer {
    )

    # Diretório local de logs (baseado na data atual)
	$agora = Get-Date
	$ano   = $agora.Year
	$mes   = $agora.Month
	$mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
	$mesNomeFormatado = (Get-Culture).TextInfo.ToTitleCase($mesNome)
	$mesFormatado = "{0:D2}. {1}" -f $mes, $mesNomeFormatado
	$diretorioLogLocal = "C:\Guardian\Logs\$ano\$mesFormatado"

    $agora = Get-Date
    $ano   = $agora.Year
    $mes   = $agora.Month
    $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
    $mesNomeFormatado = (Get-Culture).TextInfo.ToTitleCase($mesNome)
    $mesFormatado = "{0:D2}. {1}" -f $mes, $mesNomeFormatado
    $diretorioLogLocal = "C:\Guardian\Logs\$ano\$mesFormatado"

    # Seleciona o .log mais recente
    $arquivoMaisRecente = Get-ChildItem -Path $diretorioLogLocal -File -Filter '*.log' -ErrorAction SilentlyContinue |
@ -44,13 +43,13 @@ function Send-LogToServer {

    if (-not $arquivoMaisRecente) {
        Write-Host "Nenhum arquivo .log encontrado em: $diretorioLogLocal" -ForegroundColor Yellow
        Send-LogAlert  "Nenhum arquivo .log encontrado em: $diretorioLogLocal"
        Send-LogAlert "Nenhum arquivo .log encontrado em: $diretorioLogLocal"
        return
    }

    # Monta caminhos de destino
    $servidorHost   = $Server
    $servidorBase   = "\\$servidorHost\TI"
    $servidorHost    = $Server
    $servidorBase    = "\\$servidorHost\TI"
    $destinoServidor = "$servidorBase\$ano\$mesFormatado"
    $caminhoFinalServidor = Join-Path -Path $destinoServidor -ChildPath "$($env:COMPUTERNAME).log"

@ -60,31 +59,40 @@ function Send-LogToServer {
    $servidorOnline = $false
    try {
        $servidorOnline = Test-Connection -ComputerName $servidorHost -Count 1 -Quiet -TimeoutSeconds 1
    } catch { $servidorOnline = $false }
    } catch {
        $servidorOnline = $false
    }

    if (-not $servidorOnline) {
        $msg = "[ALERTA] Servidor de Arquivos '$servidorHost' não foi encontrado."
        Show-PrettyWarning $msg
        Write-Report ""
        Send-LogAlert  $msg
        Send-LogAlert $msg
        return
    }

    # =========================
    # CORREÇÃO APLICADA AQUI 👇
    # =========================

    # Força abertura de sessão SMB para evitar falso negativo no Test-Path
    try {
        cmd.exe /c "net use \\$servidorHost\TI >nul 2>&1"
    } catch {}

    # Verificação leve do compartilhamento base
    try {
        
    if (-not (Test-Path $servidorBase)) {
        $msg = "[ALERTA] Compartilhamento '$servidorBase' não acessível."
        Show-PrettyWarning $msg
        Send-LogAlert $msg
    return
    }

        if (-not (Test-Path $servidorBase)) {
            $msg = "[ALERTA] Compartilhamento '$servidorBase' não acessível."
            Show-PrettyWarning $msg
            Send-LogAlert $msg
            return
        }

    } catch {
        $msg = "Falha ao validar compartilhamento ($servidorBase)."
        Show-PrettyWarning $msg
        Write-Report ""
        Send-LogAlert  "$msg Detalhe: $($_.Exception.Message)"
        Send-LogAlert "$msg Detalhe: $($_.Exception.Message)"
        return
    }

@ -96,14 +104,14 @@ function Send-LogToServer {
    } catch {
        $msg = "Erro ao criar a pasta de destino no servidor: $($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        Send-LogAlert  $msg
        Send-LogAlert $msg
        return
    }

    # Simulado vs Cópia real
    if ($Simulado) {
        Write-Host "SIMULAÇÃO: copiaria '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'." -ForegroundColor Cyan
        Send-LogAlert  "SIMULAÇÃO: cópia de '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'."
        Send-LogAlert "SIMULAÇÃO: cópia de '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'."
        return
    }

@ -111,10 +119,10 @@ function Send-LogToServer {
        Copy-Item -Path $arquivoMaisRecente.FullName -Destination $caminhoFinalServidor -Force -ErrorAction Stop
        $okMsg = "Log '$($arquivoMaisRecente.Name)' enviado para '$caminhoFinalServidor'."
        Write-Host $okMsg -ForegroundColor Green
        Send-LogAlert  $okMsg
        Send-LogAlert $okMsg
    } catch {
        $errMsg = "Erro ao copiar para o servidor: $($_.Exception.Message)"
        Write-Host $errMsg -ForegroundColor Red
        Send-LogAlert  $errMsg
        Send-LogAlert $errMsg
    }
}
}