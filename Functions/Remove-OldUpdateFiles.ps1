# Limpa os arquivos temporários dos componentes do Windows
function Remove-OldUpdateFiles {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Host "Iniciando limpeza profunda da pasta de componentes WinSxS..." -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Limpeza profunda da pasta de componentes finalizada."
    Write-Log ""

    try {
        if (Get-Command "Dism" -ErrorAction SilentlyContinue) {
            Write-Host "Isso pode levar alguns minutos. Por favor, aguarde..." -ForegroundColor Yellow
            Write-Host ""
            
            # Executa a limpeza de componentes superseded
            # Removido /ResetBase para manter a segurança de desinstalação de patches recentes
            Dism /Online /Cleanup-Image /StartComponentCleanup /NoRestart
            
            Write-Host "Limpeza de componentes do Windows concluída com Sucesso!" -ForegroundColor Green
            Write-Host ""
            Write-Log "Limpeza de componentes do Windows concluída com Sucesso!"
            Write-Log ""
        }
        else {
            Write-Host "ERRO: O comando DISM não foi encontrado no sistema." -ForegroundColor Red
            Write-Host ""
            Write-Log "ERRO: O comando DISM não está disponível."
            Write-Log ""
        }
    }
    catch {
        Write-Host "ERRO: Falha crítica na limpeza de componentes: $_" -ForegroundColor Red
        Write-Host ""
        Write-Log "ERRO: Falha durante a limpeza de componentes do Windows: $_"
        Write-Log ""
    }
}
