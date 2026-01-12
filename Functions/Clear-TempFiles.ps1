# Limpa as pastas temporárias e realiza a limpeza de componentes do sistema (DISM)
function Clear-TempFiles {
    Write-Host "Iniciando faxina profunda e limpeza de arquivos temporários..." -ForegroundColor Cyan
    Write-Host ""

    # --- ETAPA 1: DISM (Limpeza de Componentes do Windows) ---
    # Substitui o "Windows Update Cleanup" do cleanmgr de forma 100% silenciosa.
    try {
        Write-Host "Executando DISM: Otimizando base de componentes (WinSxS)..." -ForegroundColor Yellow
        $dismArgs = "/online /Cleanup-Image /StartComponentCleanup /Quiet"
        Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -NoNewWindow
        Write-Host "Otimização de componentes concluída!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "Aviso: Não foi possível executar o DISM nesta sessão." -ForegroundColor Yellow
    }

    # --- ETAPA 2: LIMPEZA DE PASTAS TEMPORÁRIAS ---
    $alvos = @(
        "C:\Windows\Temp\*",
        "$env:TEMP\*",
        "C:\Windows\SoftwareDistribution\Download\*",
        "C:\Users\*\AppData\Local\Temp\*",
        "C:\Windows\Prefetch\*" # Adicionado Prefetch para uma limpeza mais completa
    )

    foreach ($caminho in $alvos) {
        try {
            if (Test-Path $caminho) {
                Write-Host "Limpando: $caminho" -ForegroundColor Yellow
                Remove-Item -Path $caminho -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Falha silenciosa para arquivos em uso
        }
    }

    # --- ETAPA 3: LIMPEZA DAS LIXEIRAS ---
    try {
        Write-Host ""
        Write-Host "Esvaziando lixeiras de todos os discos..." -ForegroundColor Yellow
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }
    catch { }

    Write-Host ""
    Write-Host "Limpeza profunda concluída com Sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Log "Faxina completa realizada: DISM, Pastas Temporárias e Lixeiras."
    Write-Log ""
}
