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

            Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase /NoRestart

            Write-Host "Limpeza de componentes do Windows concluída com Sucesso!" -ForegroundColor Green
            Write-Host ""

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
