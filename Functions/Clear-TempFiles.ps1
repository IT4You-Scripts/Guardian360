function Clear-TempFiles {
    [CmdletBinding()]
    param()

    try {
        # Verifica se está executando como Administrador
        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Host "Execute este script como Administrador para limpeza completa." -ForegroundColor Yellow
            Write-Log "Clear-TempFiles: execução sem privilégios administrativos."
            throw "Permissão insuficiente: requer administrador."
        }

        Write-Host "Iniciando faxina profunda e limpeza de arquivos temporários..." -ForegroundColor Cyan

        $mensagens = @()

        # --- Phase 1: DISM ---
        try {
            Write-Host "Executando DISM (WinSxS)..." -ForegroundColor Yellow
            Start-Process -FilePath "dism.exe" `
                -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /Quiet" `
                -Wait -NoNewWindow
            $mensagens += "DISM executado com sucesso"
        }
        catch {
            $mensagens += "DISM não pôde ser executado nesta sessão"
        }

        # --- Phase 2: Limpeza de temporários ---
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
            } catch {}
        }

        $mensagens += "Pastas temporárias limpas"

        # Prefetch (>7 dias)
        try {
            $prefetchPath = "C:\Windows\Prefetch"
            if (Test-Path $prefetchPath) {
                Get-ChildItem -Path $prefetchPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                $mensagens += "Prefetch antigo removido"
            }
        } catch {}

        # --- Phase 3: Lixeiras ---
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            $mensagens += "Lixeiras esvaziadas"
        } catch {}

        Write-Host "Limpeza profunda concluída com sucesso!" -ForegroundColor Green
        Write-Log "Clear-TempFiles concluído com sucesso."

        return ($mensagens -join " | ")
    }
    catch {
        Write-Host "Erro durante a limpeza de arquivos temporários." -ForegroundColor Red
        Write-Log "Erro em Clear-TempFiles: $_"
        throw $_
    }
}
