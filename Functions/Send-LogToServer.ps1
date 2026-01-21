function Send-LogToServer {
    param([Parameter(Mandatory)][string]$Server)

    $user = "guardian"
    $pass = "guardian360"

    try {
        # Localiza log mais recente
        $agora = Get-Date
        $ano   = $agora.Year
        $mes   = $agora.Month
        $mesNome = (Get-Culture).DateTimeFormat.MonthNames[$mes - 1]
        $mesFmt  = "{0:D2}. {1}" -f $mes, (Get-Culture).TextInfo.ToTitleCase($mesNome)
        $logLocal = "C:\Guardian\Logs\$ano\$mesFmt"

        if (-not (Test-Path $logLocal)) {
            Show-Header -Text "[ALERTA] Diretório de logs não encontrado: $logLocal"
            return
        }

        $arquivoLog = Get-ChildItem $logLocal -Filter '*.log' -File |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $arquivoLog) {
            Show-Header -Text "[ALERTA] Nenhum arquivo .log encontrado em $logLocal"
            return
        }

        # Destino SMB
        $destinoDir  = "\\$Server\TI\$ano\$mesFmt"
        $destinoFile = Join-Path $destinoDir "$($env:COMPUTERNAME).log"

        # Mapeia temporariamente usando o usuário guardian
        net use "\\$Server\TI" /user:$user $pass /persistent:no | Out-Null

        # Cria pasta de destino se não existir
        if (-not (Test-Path $destinoDir)) {
            New-Item -Path $destinoDir -ItemType Directory -Force | Out-Null
        }

        # Copia log
        Copy-Item $arquivoLog.FullName -Destination $destinoFile -Force

        Show-Header -Text "Log enviado com sucesso para:`n$destinoFile"

        # Desconecta o mapeamento
        net use "\\$Server\TI" /delete | Out-Null
    }
    catch {
        Show-Header -Text "[ALERTA] Erro ao copiar log para o servidor:`n$($_.Exception.Message)"
    }
}
