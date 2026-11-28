function Remove-OldUpdateFiles {
    [CmdletBinding()]
    param()

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        Write-Host "Iniciando limpeza profunda da pasta de componentes WinSxS..." -ForegroundColor Cyan
        Write-Host ""

        if (Get-Command "Dism" -ErrorAction SilentlyContinue) {
            Write-Host "Isso pode levar alguns minutos. Por favor, aguarde..." -ForegroundColor Yellow
            Write-Host ""

            # A saida do DISM continua seguindo para o pipeline (o Optimize-JsonReport le
            # "Versao" e "concluida com exito" desse texto); aqui so conferimos o codigo de saida.
            Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart
            $codigoDism = $LASTEXITCODE

            # 0 = ok; 3010 = ok, reinicializacao pendente.
            # Na falha, a mensagem NAO usa as palavras "sucesso"/"exito" (o conversor do JSON
            # considera essas palavras como indicio de que a limpeza deu certo).
            if ($codigoDism -ne 0 -and $codigoDism -ne 3010) {
                $msgDism = "DISM terminou com erro (código $codigoDism); a limpeza de componentes não foi concluída."
                Write-Host "ERRO: $msgDism" -ForegroundColor Red
                throw $msgDism
            }

            Write-Host "Limpeza de componentes do Windows concluída com Sucesso!" -ForegroundColor Green
            Write-Host ""

            if ($codigoDism -eq 3010) {
                return "StartComponentCleanup executado com sucesso via DISM (reinicialização pendente)."
            }

            return "StartComponentCleanup executado com sucesso via DISM."
        }
        else {
            $msg = "DISM não está disponível no sistema."
            Write-Host "ERRO: $msg" -ForegroundColor Red
            throw $msg
        }
    }
    catch {
        Write-Host "ERRO: Falha crítica na limpeza de componentes: $_" -ForegroundColor Red
        throw $_
    }
}
