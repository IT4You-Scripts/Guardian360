
function Send-LogToServer {
    param([Parameter(Mandatory)][string]$Server)

    $user = "guardian"
    $pass = "guardian360"

    try {
        # Verifica se o servidor responde ao ping
        if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Show-Header -Text "[ALERTA] Servidor $Server não está acessível (ping falhou)." -Color $Red
            return
        }

        # Localiza log mais recente
        $agora = Get-Date
        $ano   = $agora.Year
        $mes   = $agora.Month
        $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
        $mesFmt  = "{0:D2}. {1}" -f $mes, (Get-Culture).TextInfo.ToTitleCase($mesNome)
        $logLocal = "C:\Guardian\Logs\$ano\$mesFmt"

        if (-not (Test-Path $logLocal)) {
            Show-Header -Text "[ALERTA] Diretório de logs não encontrado: $logLocal" -Color $Yellow
            return
        }

        $arquivoLog = Get-ChildItem $logLocal -Filter '*.log' -File |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $arquivoLog) {
            Show-Header -Text "[ALERTA] Nenhum arquivo .log encontrado em $logLocal" -Color $Yellow
            return
        }

        # Destino SMB
        $destinoDir  = "\\$Server\TI\$ano\$mesFmt"
        $destinoFile = Join-Path $destinoDir "$($env:COMPUTERNAME).log"

        # Primeira tentativa: copiar usando credenciais salvas
        try {
            Copy-Item $arquivoLog.FullName -Destination $destinoFile -Force -ErrorAction Stop
            Show-Header -Text "Log enviado com sucesso para: $destinoFile (usando credenciais salvas)" -Color $Green
        }
        catch {
            Show-Header -Text "[INFO] Falha na cópia com credenciais salvas. Tentando com credenciais guardian..." -Color $Yellow

            try {
                # Mapeia temporariamente usando usuário guardian
                net use "\\$Server\TI" /user:$user $pass /persistent:no | Out-Null

                # Cria pasta de destino se não existir (agora autenticado)
                if (-not (Test-Path $destinoDir)) {
                    New-Item -Path $destinoDir -ItemType Directory -Force | Out-Null
                }

                # Copia log com credenciais guardian
                Copy-Item $arquivoLog.FullName -Destination $destinoFile -Force -ErrorAction Stop
                Show-Header -Text "Log enviado com sucesso para: $destinoFile (usando credenciais guardian)" -Color $Green
            }
            catch {
                Show-Header -Text "[ERRO] Falha ao copiar log mesmo após tentar com credenciais guardian.`n$($_.Exception.Message)" -Color $Red
            }
            finally {
                # Desconecta o mapeamento
                net use "\\$Server\TI" /delete | Out-Null
            }
        }
    }
    catch {
        Show-Header -Text "[ALERTA] Erro inesperado: $($_.Exception.Message)" -Color $Red
    }
}
