function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # 1. Validação da base local
    # ------------------------------------------------------------------
    $baseLogs = "C:\Guardian\Logs"

    if (-not (Test-Path $baseLogs)) {
        Write-Host "Base de logs inexistente: $baseLogs" -ForegroundColor Yellow
        return
    }

    # ------------------------------------------------------------------
    # 2. Ano mais recente
    # ------------------------------------------------------------------
    $anoDir = Get-ChildItem $baseLogs -Directory |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $anoDir) {
        Write-Host "Nenhum diretório de ano encontrado." -ForegroundColor Yellow
        return
    }

    # ------------------------------------------------------------------
    # 3. Mês mais recente
    # ------------------------------------------------------------------
    $mesDir = Get-ChildItem $anoDir.FullName -Directory |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $mesDir) {
        Write-Host "Nenhum diretório de mês encontrado." -ForegroundColor Yellow
        return
    }

    # ------------------------------------------------------------------
    # 4. Log mais recente
    # ------------------------------------------------------------------
    $log = Get-ChildItem $mesDir.FullName -Filter *.log -File |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1

    if (-not $log) {
        Write-Host "Nenhum arquivo .log encontrado." -ForegroundColor Yellow
        return
    }

    # ------------------------------------------------------------------
    # 5. Validação DNS (leve, não bloqueante)
    # ------------------------------------------------------------------
    try {
        [void][System.Net.Dns]::GetHostEntry($Server)
    } catch {
        Write-Host "[AVISO] DNS não validado para '$Server'. Tentando SMB mesmo assim..." -ForegroundColor Yellow
    }

    # ------------------------------------------------------------------
    # 6. Validação SMB real
    # ------------------------------------------------------------------
    $destinoBase = "\\$Server\TI"

    if (-not (Test-Path $destinoBase)) {
        $msg = "[ALERTA] Compartilhamento '$destinoBase' não acessível."
        Show-PrettyWarning $msg

        if (Get-Command Send-LogAlert -ErrorAction SilentlyContinue) {
            Send-LogAlert $msg
        }
        return
    }

    # ------------------------------------------------------------------
    # 7. Aguarda o log SER FECHADO (anti-arquivo cortado)
    # ------------------------------------------------------------------
    Write-Host "Aguardando finalização real do arquivo de log..." -ForegroundColor Yellow

    if (-not (Wait-FileUnlocked -Path $log.FullName -TimeoutSeconds 20)) {
        Write-Host "ERRO: log ainda em uso após timeout." -ForegroundColor Red
        return
    }

    # ------------------------------------------------------------------
    # 8. Estrutura no servidor
    # ------------------------------------------------------------------
    $destinoFinal = Join-Path $destinoBase "$($anoDir.Name)\$($mesDir.Name)"
    $arquivoDestino = Join-Path $destinoFinal "$($env:COMPUTERNAME).log"

    try {
        if (-not (Test-Path $destinoFinal)) {
            New-Item -ItemType Directory -Path $destinoFinal -Force | Out-Null
        }
    } catch {
        Write-Host "Erro ao criar diretório no servidor." -ForegroundColor Red
        return
    }

    # ------------------------------------------------------------------
    # 9. Cópia FINAL (arquivo completo)
    # ------------------------------------------------------------------
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
