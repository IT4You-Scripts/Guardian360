$ErrorActionPreference = 'Stop'

function Send-LogAlert  {
    param([string]$text)
    try {
        if (Get-Command Write-Report -ErrorAction SilentlyContinue) {
            Write-Report -Text $text
        }
    } catch {}
}

function Show-PrettyWarning {
    param([string]$text)
    $len = $text.Length + 2
    Write-Host ("") -ForegroundColor Yellow
    Write-Host ("┌" + ("─" * $len) + "┐") -ForegroundColor Yellow
    Write-Host ("│ $text │") -ForegroundColor Yellow
    Write-Host ("└" + ("─" * $len) + "┘") -ForegroundColor Yellow
    Write-Host ("") -ForegroundColor Yellow
}

function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,     # IP/Hostname (ex.: 192.168.0.2 ou Servidor)
        [switch]$Simulado    # Modo simulado: não efetua a cópia
    )

    # Diretório local de logs (baseado na data atual)
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
        Write-Host "Nenhum arquivo .log encontrado em: $diretorioLogLocal" -ForegroundColor Yellow
        Send-LogAlert  "Nenhum arquivo .log encontrado em: $diretorioLogLocal"
        return
    }

    # Monta caminhos de destino
    $servidorHost   = $Server
    $servidorBase   = "\\$servidorHost\TI"
    $destinoServidor = "$servidorBase\$ano\$mesFormatado"
    $caminhoFinalServidor = Join-Path -Path $destinoServidor -ChildPath "$($env:COMPUTERNAME).log"

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # Verificação rápida de disponibilidade (ping curto)
    $servidorOnline = $false
    try {
        $servidorOnline = Test-Connection -ComputerName $servidorHost -Count 1 -Quiet -TimeoutSeconds 1
    } catch { $servidorOnline = $false }

    if (-not $servidorOnline) {
        $msg = "[ALERTA] Servidor de Arquivos '$servidorHost' não foi encontrado."
        Show-PrettyWarning $msg
        Write-Report ""
        Send-LogAlert  $msg
        return
    }

    # Verificação leve do compartilhamento base
    try {
        
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
        return
    }

    # Garante a estrutura de destino
    try {
        if (-not ([System.IO.Directory]::Exists($destinoServidor))) {
            [void][System.IO.Directory]::CreateDirectory($destinoServidor)
        }
    } catch {
        $msg = "Erro ao criar a pasta de destino no servidor: $($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        Send-LogAlert  $msg
        return
    }

    # Simulado vs Cópia real
    if ($Simulado) {
        Write-Host "SIMULAÇÃO: copiaria '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'." -ForegroundColor Cyan
        Send-LogAlert  "SIMULAÇÃO: cópia de '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'."
        return
    }

    try {
        Copy-Item -Path $arquivoMaisRecente.FullName -Destination $caminhoFinalServidor -Force -ErrorAction Stop
        $okMsg = "Log '$($arquivoMaisRecente.Name)' enviado para '$caminhoFinalServidor'."
        Write-Host $okMsg -ForegroundColor Green
        Send-LogAlert  $okMsg
    } catch {
        $errMsg = "Erro ao copiar para o servidor: $($_.Exception.Message)"
        Write-Host $errMsg -ForegroundColor Red
        Send-LogAlert  $errMsg
    }
}