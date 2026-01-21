function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,
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

    # Log mais recente
    $logOriginal = Get-ChildItem -Path $diretorioLogLocal -File -Filter '*.log' |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

    if (-not $logOriginal) {
        Write-Host "[AVISO] Nenhum log encontrado." -ForegroundColor Yellow
        return
    }

    # 🔒 CLONE FECHADO (PONTO-CHAVE)
    $logTemp = Join-Path $env:TEMP "$($env:COMPUTERNAME).log"
    Copy-Item -Path $logOriginal.FullName -Destination $logTemp -Force

    # Destino
    $destinoServidor = "\\$Server\TI\$ano\$mesFormatado"
    $nomeFinalLog    = "$($env:COMPUTERNAME).log"

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    if ($Simulado) {
        Write-Host "SIMULAÇÃO: $logTemp -> $destinoServidor\$nomeFinalLog" -ForegroundColor Cyan
        return
    }

    # Robocopy APENAS do clone
    $argumentos = @(
        "`"$([System.IO.Path]::GetDirectoryName($logTemp))`"",
        "`"$destinoServidor`"",
        "`"$([System.IO.Path]::GetFileName($logTemp))`"",
        "/R:1",
        "/W:1",
        "/NFL",
        "/NDL",
        "/NJH",
        "/NJS",
        "/NC",
        "/NS"
    ) -join ' '

    $proc = Start-Process robocopy.exe -ArgumentList $argumentos -Wait -NoNewWindow -PassThru

    if ($proc.ExitCode -ge 8) {
        Write-Host "[ERRO] Falha ao enviar log (ExitCode $($proc.ExitCode))" -ForegroundColor Red
        return
    }

    # Limpeza
    Remove-Item $logTemp -Force -ErrorAction SilentlyContinue

    Write-Host "Log enviado com sucesso: $nomeFinalLog" -ForegroundColor Green
}
