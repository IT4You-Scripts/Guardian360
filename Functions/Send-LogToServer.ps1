function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [switch]$Simulado   # <-- MANTIDO por compatibilidade
    )

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # Base local
    $baseLogs = "C:\Guardian\Logs"

    if (-not (Test-Path $baseLogs)) {
        Write-Host "Base de logs inexistente: $baseLogs" -ForegroundColor Yellow
        return
    }

    # Ano mais recente
    $anoDir = Get-ChildItem $baseLogs -Directory |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $anoDir) { return }

    # Mês mais recente
    $mesDir = Get-ChildItem $anoDir.FullName -Directory |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $mesDir) { return }

    # Log mais recente
    $log = Get-ChildItem $mesDir.FullName -Filter *.log -File |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1

    if (-not $log) {
        Write-Host "Nenhum log encontrado." -ForegroundColor Yellow
        return
    }

    # Validação DNS leve (não bloqueante)
    try {
        [void][System.Net.Dns]::GetHostEntry($Server)
    } catch {
        Write-Host "[AVISO] DNS não validado para '$Server'. Tentando SMB mesmo assim..." -ForegroundColor Yellow
    }

    # Caminhos remotos
    $destinoBase  = "\\$Server\TI"
    $destinoFinal = Join-Path $destinoBase "$($anoDir.Name)\$($mesDir.Name)"
    $arquivoDestino = Join-Path $destinoFinal "$($env:COMPUTERNAME).log"

    # Validação SMB real
    if (-not (Test-Path $destinoBase)) {
        $msg = "[ALERTA] Compartilhamento '$destinoBase' não acessível."
        Show-PrettyWarning $msg
        if (Get-Command Send-LogAlert -ErrorAction SilentlyContinue) {
            Send-LogAlert $msg
        }
        return
    }

    # Aguarda o log ser FECHADO
    Write-Host "Aguardando finalização do arquivo de log..." -ForegroundColor Yellow

    if (-not (Wait-FileUnlocked -Path $log.FullName -TimeoutSeconds 20)) {
        Write-Host "ERRO: Log ainda em uso após timeout." -ForegroundColor Red
        return
    }

    # Garante estrutura no servidor
    try {
        if (-not (Test-Path $destinoFinal)) {
            New-Item -ItemType Directory -Path $destinoFinal -Force | Out-Null
        }
    } catch {
        Write-Host "Erro ao criar diretório no servidor." -ForegroundColor Red
        return
    }

    # Simulação (mantida apenas por compatibilidade)
    if ($Simulado) {
        Write-Host "SIMULAÇÃO: '$($log.FullName)' -> '$arquivoDestino'" -ForegroundColor Cyan
        return
    }

    # Cópia FINAL (arquivo completo)
    try {
        Copy-Item -Path $log.FullName -Destination $arquivoDestino -Force
        Write-Host "Log copiado COMPLETO: $arquivoDestino" -ForegroundColor Green

        if (Get-Command Send-LogAlert -ErrorAction SilentlyContinue) {
            Send-LogAlert "Log enviado com sucesso: $arquivoDestino"
        }

    } catch {
        Write-Host "Erro ao copiar log: $($_.Exception.Message)" -ForegroundColor Red
    }
}
