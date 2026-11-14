function Clear-RecentFilesHistory {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Limpeza do histórico de arquivos recentes." -ForegroundColor Cyan

        $recentItems = [System.Environment]::GetFolderPath('Recent')

        if (-not (Test-Path $recentItems)) {
            return "Pasta de itens recentes não encontrada."
        }

        # Garante que sempre será uma coleção (mesmo que vazia)
        $items = @( Get-ChildItem -Path $recentItems -Force -ErrorAction Stop )
        $count = $items.Count

        if ($count -gt 0) {
            Remove-Item "$recentItems\*" -Force -Recurse -Confirm:$false -ErrorAction Stop
        }

        return "Histórico limpo. Itens removidos=$count"
    }
    catch {
        Write-Host "Erro durante a limpeza do histórico de arquivos recentes." -ForegroundColor Red
        throw $_
    }
}