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
        [string]$Server
    )

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # ==========================================================
    # 1. BASE LOCAL DE LOGS
    # ==========================================================
    $baseLogs = "C:\Guardian\Logs"

    if (-not (Test-Path $baseLogs)) {
        $msg = "Base de logs inexistente: $baseLogs"
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 2. ANO MAIS RECENTE
    # ==========================================================
    $anoDir = Get-ChildItem -Path $baseLogs -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $anoDir) {
        $msg = "Nenhum diretório de ano encontrado."
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 3. MÊS MAIS RECENTE
    # ==========================================================
    $mesDir = Get-ChildItem -Path $anoDir.FullName -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending |
              Select-Object -First 1

    if (-not $mesDir) {
        $msg = "Nenhum diretório de mês encontrado."
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 4. ARQUIVO DE LOG MAIS RECENTE (REAL)
    # ==========================================================
    $arquivo = Get-ChildItem -Path $mesDir.FullName -Filter '*.log' -File -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

    if (-not $arquivo) {
        $msg = "Nenhum arquivo .log encontrado em: $($mesDir.FullName)"
        Write-Host $msg -ForegroundColor Yellow
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 5. DESTINO NO SERVIDOR
    # ==========================================================
    $destinoBase = "\\$Server\TI\$($anoDir.Name)\$($mesDir.Name)"
    $nomeFinal   = "$($env:COMPUTERNAME).log"
    $destinoLog  = Join-Path $destinoBase $nomeFinal

    # ==========================================================
    # 6. VALIDAÇÃO SMB REAL
    # ==========================================================
    if (-not (Test-Path "\\$Server\TI")) {
        $msg = "[ALERTA] Compartilhamento '\\$Server\TI' não acessível."
        Write-Host $msg -ForegroundColor Red
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 7. CRIA ESTRUTURA NO SERVIDOR
    # ==========================================================
    try {
        if (-not (Test-Path $destinoBase)) {
            New-Item -ItemType Directory -Path $destinoBase -Force | Out-Null
        }
    } catch {
        $msg = "Erro ao criar diretório no servidor: $($_.Exception.Message)"
        Write-Host $msg -ForegroundColor Red
        Send-LogAlert $msg
        return
    }

    # ==========================================================
    # 8. CÓPIA FINAL (SIMPLES, ÍNTEGRA, SEM TRUNCAR)
    # ==========================================================
    try {
        Copy-Item `
            -Path $arquivo.FullName `
            -Destination $destinoLog `
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
