# Limpa o histórico de arquivos recentes
function Clear-RecentFilesHistory {
    Write-Host "Limpeza do histórico de arquivos recentes."
    try {
        $recentItems = [System.Environment]::GetFolderPath('Recent')
        Remove-Item "$recentItems\*" -Force -Recurse -Confirm:$false -ErrorAction Stop
        Write-Log "Limpeza do histórico de arquivos recentes concluída com sucesso."
    }
    catch {
        Write-Log "Erro durante a limpeza do histórico de arquivos recentes: $_"
    }
}
