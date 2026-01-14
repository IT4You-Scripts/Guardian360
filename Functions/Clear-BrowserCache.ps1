# Limpa o cache dos navegadores
function Clear-BrowserCache {
    Write-Host "Iniciando limpeza de cache dos navegadores..." -ForegroundColor Cyan

    try {
        # 1. Encerra os navegadores em execução
        $browsers = @("chrome", "msedge", "firefox")
        $running = Get-Process -Name $browsers -ErrorAction SilentlyContinue

        foreach ($proc in $running) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $proc.Id -ErrorAction SilentlyContinue
        }

        # 2. Chrome / Edge (Chromium)
        $chromiumPaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        )

        foreach ($path in $chromiumPaths) {
            if (Test-Path $path) {
                Get-ChildItem -Path $path -Directory -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -in "Cache", "GPUCache", "Code Cache" } |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # 3. Firefox
        $firefoxProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
        if (Test-Path $firefoxProfiles) {
            Get-ChildItem -Path $firefoxProfiles -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in "cache2", "jumpListCache", "startupCache" } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Cache dos navegadores limpo com sucesso." -ForegroundColor Green
        Write-Log "Cache dos navegadores limpo."
    }
    catch {
        Write-Host "Não foi possível limpar o cache dos navegadores." -ForegroundColor Red
        Write-Log "Erro ao limpar cache dos navegadores: $_"
    }
}
