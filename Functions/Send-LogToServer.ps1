# Copia o arquivo de log para o Servidor de Arquivos da rede local, caso exista
function Send-LogToServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,     # Host/IP do servidor (ex.: 192.168.0.2 ou SERVIDOR)
        [switch]$Simulado    # Modo simulado: não efetua a cópia
    )

    $ErrorActionPreference = 'Stop'

    # --- Configuração base ---
    $caminhoBaseLocal = 'C:\IT4You\TI'
    $data  = Get-Date
    $ano   = $data.Year
    $mesNumero = $data.ToString('MM')
    $mesNome   = (Get-Culture).TextInfo.ToTitleCase($data.ToString('MMMM'))
    $pastaMes  = "$mesNumero. $mesNome"

    $diretorioLogLocal = Join-Path -Path $caminhoBaseLocal -ChildPath "$ano\$pastaMes"

    # Servidor informado via parâmetro
    $servidorHost = $Server
    $servidorBase = "\$servidorHost\TI"
    $destinoServidor = "$servidorBase\$ano\$pastaMes"

    Write-Host "Centralizando log no servidor..." -ForegroundColor Cyan

    # --- 1) Verificação rápida da pasta local ---
    if (-not (Test-Path -Path $diretorioLogLocal)) {
        Write-Host "Pasta local de logs não encontrada: $diretorioLogLocal" -ForegroundColor Red
        return
    }

    # --- 2) Seleção do .log mais recente ---
    $arquivoMaisRecente = Get-ChildItem -Path $diretorioLogLocal -File -Filter '*.log' -ErrorAction SilentlyContinue |
                          Sort-Object LastWriteTime -Descending |
                          Select-Object -First 1

    if (-not $arquivoMaisRecente) {
        Write-Host "Nenhum arquivo .log encontrado em: $diretorioLogLocal" -ForegroundColor Yellow
        return
    }

    # --- 3) Verificação super-rápida de disponibilidade do servidor (ping) ---
    $servidorOnline = $false
    try {
        $servidorOnline = Test-Connection -ComputerName $servidorHost -Count 1 -Quiet -TimeoutSeconds 1
    } catch {
        $servidorOnline = $false
    }

    if (-not $servidorOnline) {
        Write-Host "Servidor de arquivos ($servidorBase) inacessível (ping falhou). Operação ignorada rapidamente." -ForegroundColor Yellow
        return
    }

    # --- 4) Verificação leve do compartilhamento ---
    try {
        if (-not ([System.IO.Directory]::Exists($servidorBase))) {
            Write-Host "Compartilhamento TI indisponível em $servidorBase. Operação ignorada." -ForegroundColor Yellow
            return
        }
    } catch {
        Write-Host "Falha ao validar compartilhamento ($servidorBase). Operação ignorada. Detalhe: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }

    # --- 5) Cria estrutura de destino somente se necessário ---
    try {
        if (-not ([System.IO.Directory]::Exists($destinoServidor))) {
            [void][System.IO.Directory]::CreateDirectory($destinoServidor)
        }
    } catch {
        Write-Host "Erro ao criar a pasta de destino no servidor: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # --- 6) Copia com nome padronizado (NomeDoComputador.log) ---
    $caminhoFinalServidor = Join-Path -Path $destinoServidor -ChildPath "$($env:COMPUTERNAME).log"

    if ($Simulado) {
        Write-Host "SIMULADO: copiaria '$($arquivoMaisRecente.FullName)' para '$caminhoFinalServidor'." -ForegroundColor Cyan
        return
    }

    try {
        Copy-Item -Path $arquivoMaisRecente.FullName -Destination $caminhoFinalServidor -Force -ErrorAction Stop
        Write-Host "Log '$($arquivoMaisRecente.Name)' enviado para '$caminhoFinalServidor'." -ForegroundColor Green
    } catch {
        Write-Host "Erro ao copiar para o servidor: $($_.Exception.Message)" -ForegroundColor Red
    }
}