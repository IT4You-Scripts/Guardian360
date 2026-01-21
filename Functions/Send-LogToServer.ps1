# ===============================
# FALLBACK DE ALERTA (BLINDADO)
# ===============================
if (-not (Get-Command Send-LogAlert -ErrorAction SilentlyContinue)) {
    function Send-LogAlert {
        param([string]$Text)
        # fallback silencioso
    }
}

function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        [switch]$Simulado
    )

    # ===============================
    # LOG LOCAL
    # ===============================
    $agora = Get-Date
    $ano   = $agora.Year
    $mes   = $agora.Month
    $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
    $mesNomeFormatado = (Get-Culture).TextInfo.ToTitleCase($mesNome)
    $mesFormatado = "{0:D2}. {1}" -f $mes, $mesNomeFormatado
    $diretorioLogLocal = "C:\Guardian\Logs\$ano\$mesFormatado"

    $arquivo = Get-ChildItem `
        -Path $diretorioLogLocal `
        -Filter '*.log' `
        -File `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $arquivo) {
        $msg = "Nenhum arquivo .log encontrado em: $diretorioLogLocal"
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # ===============================
    # DESTINO
    # ===============================
    $destinoBase = "\\$Server\TI\$ano\$mesFormatado"
    $nomeFinal   = "$($env:COMPUTERNAME).log"

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # ===============================
    # SIMULAÇÃO
    # ===============================
    if ($Simulado) {
        $msg = "SIMULAÇÃO: '$($arquivo.FullName)' -> '$destinoBase\$nomeFinal'"
        Write-Host $msg -ForegroundColor Cyan
        Send-LogAlert $msg
        return
    }

    try {
        # Garante pasta
        if (-not (Test-Path $destinoBase)) {
            New-Item -ItemType Directory -Path $destinoBase -Force | Out-Null
        }

        # CÓPIA COM RENOMEAÇÃO (CORRETO)
        Copy-Item `
            -Path $arquivo.FullName `
            -Destination "$destinoBase\$nomeFinal" `
            -Force `
            -ErrorAction Stop

        $okMsg = "Log '$nomeFinal' enviado com sucesso para '$destinoBase'."
        Write-Host $okMsg -ForegroundColor Green
        Send-LogAlert $okMsg

    } catch {
        $errMsg = "Erro ao enviar log: $($_.Exception.Message)"
        Write-Host $errMsg -ForegroundColor Red
        Send-LogAlert $errMsg
    }
}
