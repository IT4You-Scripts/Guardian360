function Send-LogToServer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server)

    # Cronômetro
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $user = "guardian"
    $pass = "guardian360"

    try {
        # Verifica acessibilidade do servidor
        if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {

            Show-Header -Text "[ALERTA] Servidor $Server não está acessível (ping falhou)." -Color $Red

            $sw.Stop()
            if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                Write-JsonResult -Phase "Send-LogToServer" `
                                 -Sucesso $false `
                                 -Tempo $sw.Elapsed `
                                 -Mensagem "Servidor $Server inacessível (ping falhou)."
            }
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

            $sw.Stop()
            if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                Write-JsonResult -Phase "Send-LogToServer" `
                                 -Sucesso $false `
                                 -Tempo $sw.Elapsed `
                                 -Mensagem "Diretório de logs não encontrado: $logLocal"
            }
            return
        }

        $arquivoLog = Get-ChildItem $logLocal -Filter '*.log' -File |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if (-not $arquivoLog) {

            Show-Header -Text "[ALERTA] Nenhum arquivo .log encontrado em $logLocal" -Color $Yellow

            $sw.Stop()
            if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                Write-JsonResult -Phase "Send-LogToServer" `
                                 -Sucesso $false `
                                 -Tempo $sw.Elapsed `
                                 -Mensagem "Nenhum arquivo .log encontrado em $logLocal"
            }
            return
        }

        # Destino SMB
        $destinoDir  = "\\$Server\TI\Vistorias\$ano\$mesFmt"
        $destinoFile = Join-Path $destinoDir "$($env:COMPUTERNAME).log"

        # Cria diretório no servidor
        if (-not (Test-Path $destinoDir)) {
            New-Item -Path $destinoDir -ItemType Directory -Force | Out-Null
        }

        # Primeira tentativa (credenciais salvas)
        try {
            Copy-Item $arquivoLog.FullName -Destination $destinoFile -Force -ErrorAction Stop

            Show-Header -Text "Log enviado com sucesso para: $destinoFile (credenciais salvas)" -Color $Green

            $sw.Stop()
            if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                Write-JsonResult -Phase "Send-LogToServer" `
                                 -Sucesso $true `
                                 -Tempo $sw.Elapsed `
                                 -Mensagem "Log enviado com sucesso usando credenciais salvas."
            }
        }
        catch {
            Show-Header -Text "[INFO] Falha com credenciais salvas. Tentando guardian..." -Color $Yellow

            try {
                # Mapeia \\Server\TI
                net use "\\$Server\TI" /user:$user $pass /persistent:no | Out-Null

                if (-not (Test-Path $destinoDir)) {
                    New-Item -Path $destinoDir -ItemType Directory -Force | Out-Null
                }

                Copy-Item $arquivoLog.FullName -Destination $destinoFile -Force -ErrorAction Stop

                Show-Header -Text "Log enviado com sucesso para: $destinoFile (credenciais guardian)" -Color $Green

                $sw.Stop()
                if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                    Write-JsonResult -Phase "Send-LogToServer" `
                                     -Sucesso $true `
                                     -Tempo $sw.Elapsed `
                                     -Mensagem "Log enviado via credenciais guardian."
                }
            }
            catch {
                Show-Header -Text "[ERRO] Falha ao copiar log mesmo com guardian.`n$($_.Exception.Message)" -Color $Red

                $sw.Stop()
                $erro = $_ | Format-List * -Force | Out-String

                if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
                    Write-JsonResult -Phase "Send-LogToServer" `
                                     -Sucesso $false `
                                     -Tempo $sw.Elapsed `
                                     -Mensagem $erro
                }
            }
            finally {
                net use "\\$Server\TI" /delete | Out-Null
            }
        }
    }
    catch {
        Show-Header -Text "[ALERTA] Erro inesperado: $($_.Exception.Message)" -Color $Red

        $sw.Stop()
        $erro = $_ | Format-List * -Force | Out-String

        if (Get-Command Write-JsonResult -ErrorAction SilentlyContinue) {
            Write-JsonResult -Phase "Send-LogToServer" `
                             -Sucesso $false `
                             -Tempo $sw.Elapsed `
                             -Mensagem $erro
        }
    }
}