# Limpa o cache dos navegadores 
function Clear-BrowserCache {
    Write-Host "Iniciando limpeza profunda de navegadores..." -ForegroundColor Cyan
    Write-Host ""

    # 1. Encerra os processos para liberar os arquivos
    $browsers = "chrome", "msedge", "firefox"
    foreach ($b in $browsers) {
        if (Get-Process $b -ErrorAction SilentlyContinue) {
            Write-Host "Fechando $b para permitir a limpeza..." -ForegroundColor Yellow
            Write-Host ""
            Stop-Process -Name $b -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2 # Tempo para o SO liberar os handles de arquivo
        }
    }

    # 2. Limpeza Chrome e Edge (Base Chromium)
    $chromiumPaths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    )

    foreach ($path in $chromiumPaths) {
        if (Test-Path $path) {
            # Limpa pastas de cache em todos os perfis (Default e Profile X)
            Get-ChildItem -Path $path -Include "Cache", "GPUCache", "Code Cache" -Recurse -ErrorAction SilentlyContinue | 
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Limpeza Firefox
    $firefoxProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" # Cache do FF fica no Local, não no Roaming
    if (Test-Path $firefoxProfiles) {
        Get-ChildItem -Path $firefoxProfiles -Include "cache2", "jumpListCache", "startupCache" -Recurse -ErrorAction SilentlyContinue | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

     Write-Host ""
	 Write-Host "Limpeza dos navegadores concluída!" -ForegroundColor Green
    Write-Host ""
    Write-Log ""
	Write-Log "Limpeza dos navegadores concluída."
    Write-Log ""
}
