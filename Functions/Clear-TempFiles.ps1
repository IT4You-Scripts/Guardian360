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
            throw "Permissão insuficiente: requer administrador."
        }

        Write-Host "Iniciando faxina profunda e limpeza de arquivos temporários..." -ForegroundColor Cyan

        $mensagens = @()

        # Parâmetros de segurança
        $idadeMinDias   = 3    # nas pastas Temp de usuários, só apaga o que tem mais de N dias

        # O DISM (StartComponentCleanup) não é executado aqui: Remove-OldUpdateFiles
        # já faz essa limpeza (com /ResetBase), depois das atualizações do Windows.

        # --- Phase 1: Limpeza de temporários ---
        Write-Host "Limpando pastas temporárias..." -ForegroundColor Yellow

        $stats = @{ Removidos = 0; EmUso = 0; Recentes = 0; AtalhosIgnorados = 0 }

        # Apaga o conteúdo de uma pasta (não a pasta em si).
        # - Não segue junctions/links simbólicos (pontos de reanálise): ignora
        # - Se $Limite for informado, só apaga arquivos com LastWriteTime anterior a ele
        function Remove-ConteudoDaPasta {
            param(
                [string]$Pasta,
                $Limite
            )

            $itens = @(Get-ChildItem -LiteralPath $Pasta -Force -ErrorAction SilentlyContinue)
            foreach ($item in $itens) {
                try {
                    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                        $stats.AtalhosIgnorados++
                        continue
                    }

                    if ($item.PSIsContainer) {
                        Remove-ConteudoDaPasta -Pasta $item.FullName -Limite $Limite

                        # Pasta recente é mantida quando há filtro de idade
                        if ($null -ne $Limite -and $item.LastWriteTime -ge $Limite) { continue }

                        # Só remove a pasta se ficou vazia
                        $sobrou = @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
                        if ($sobrou.Count -eq 0) {
                            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                        }
                    }
                    else {
                        if ($null -ne $Limite -and $item.LastWriteTime -ge $Limite) {
                            $stats.Recentes++
                            continue
                        }
                        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                        $stats.Removidos++
                    }
                }
                catch {
                    $stats.EmUso++
                }
            }
        }

        $limiteIdade = (Get-Date).AddDays(-$idadeMinDias)

        # Lista de alvos: Pasta + indicador de filtro por idade (somente perfis de usuário)
        $alvos = @()
        $alvos += @{ Pasta = "C:\Windows\Temp";                          Filtrar = $false }
        $alvos += @{ Pasta = $env:TEMP;                                  Filtrar = ($env:TEMP -like "C:\Users\*") }
        # SoftwareDistribution\Download é tratado por Clear-WindowsUpdateCache (que para os serviços antes)

        $perfis = @(Get-ChildItem -LiteralPath "C:\Users" -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($perfil in $perfis) {
            if ($perfil.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $alvos += @{ Pasta = (Join-Path $perfil.FullName "AppData\Local\Temp"); Filtrar = $true }
        }

        $jaFeitos = @{}
        foreach ($alvo in $alvos) {
            $pasta = $alvo.Pasta
            if ([string]::IsNullOrWhiteSpace($pasta)) { continue }

            $chave = $pasta.TrimEnd('\').ToLowerInvariant()
            if ($jaFeitos.ContainsKey($chave)) { continue }
            $jaFeitos[$chave] = $true

            try {
                if (-not (Test-Path -LiteralPath $pasta -PathType Container)) { continue }

                $info = Get-Item -LiteralPath $pasta -Force -ErrorAction Stop
                if ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $stats.AtalhosIgnorados++
                    continue
                }

                $limite = $null
                if ($alvo.Filtrar) { $limite = $limiteIdade }
                Remove-ConteudoDaPasta -Pasta $pasta -Limite $limite
            }
            catch {}
        }

        $resumo = "Pastas temporárias limpas ($($stats.Removidos) arquivos removidos"
        if ($stats.EmUso -gt 0)            { $resumo += ", $($stats.EmUso) em uso ou sem permissão" }
        if ($stats.Recentes -gt 0)         { $resumo += ", $($stats.Recentes) recentes mantidos" }
        if ($stats.AtalhosIgnorados -gt 0) { $resumo += ", $($stats.AtalhosIgnorados) atalhos de pasta ignorados" }
        $resumo += ")"
        $mensagens += $resumo

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

        # --- Phase 2: Lixeiras ---
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            $mensagens += "Lixeiras esvaziadas"
        } catch {}

        Write-Host "Limpeza profunda concluída com sucesso!" -ForegroundColor Green

        return ($mensagens -join " | ")
    }
    catch {
        Write-Host "Erro durante a limpeza de arquivos temporários." -ForegroundColor Red
        throw $_
    }
}
