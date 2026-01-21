function Clear-TempFiles {
    # Verifica se está executando como Administrador
    if (-not ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Execute este script como Administrador para limpeza completa." -ForegroundColor Yellow
        return
    }

    Write-Host "Iniciando faxina profunda e limpeza de arquivos temporários..." -ForegroundColor Cyan

    # --- ETAPA 1: DISM ---
    try {
        Write-Host "Executando DISM: Otimizando base de componentes (WinSxS). Isso pode levar alguns minutos..." -ForegroundColor Yellow
        Start-Process -FilePath "dism.exe" -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /Quiet" -Wait -NoNewWindow
        Write-Host "Otimização de componentes concluída!" -ForegroundColor Green
    }
    catch {
        Write-Host "Aviso: Não foi possível executar o DISM nesta sessão." -ForegroundColor Yellow
    }

    # --- ETAPA 2: Limpeza de pastas temporárias ---
    Write-Host "Limpando pastas temporárias..." -ForegroundColor Yellow

    $alvos = @(
        "C:\Windows\Temp\*",
        "$env:TEMP\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "C:\Users\*\AppData\Local\Temp\*"
    )

    foreach ($caminho in $alvos) {
        try {
            Remove-Item -Path $caminho -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # falha silenciosa em arquivos bloqueados
        }
    }

    # Limpeza opcional de Prefetch (apenas arquivos > 7 dias)
    try {
        $prefetchPath = "C:\Windows\Prefetch"
        if (Test-Path $prefetchPath) {
            Get-ChildItem -Path $prefetchPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }

    # --- ETAPA 3: Limpeza de lixeiras ---
    try {
        Write-Host "Esvaziando lixeiras de todos os discos..." -ForegroundColor Yellow
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }
    catch { }

    Write-Host "Limpeza profunda concluída com sucesso!" -ForegroundColor Green
    Write-Log "Faxina completa realizada: DISM, pastas temporárias e lixeiras."
}
