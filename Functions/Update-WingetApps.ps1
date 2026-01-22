
function Update-WingetApps {
    [CmdletBinding()]
    param()

    Show-Header -Text "Iniciando atualização seletiva de programas via Winget..." -Color $Cyan
    Write-Log 'Iniciando atualização seletiva de programas via Winget...' 'INFO'

    # Verifica se o Winget está disponível
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Show-Header -Text "Winget não está disponível. Etapa ignorada." -Color $Yellow
        Write-Log 'Winget não está disponível. Etapa ignorada.' 'WARN'
        return
    }

    # Lista de programas bloqueados (Blacklist)
    $blacklistedIds = @('QGIS.QGIS','TeamViewer.TeamViewer','SiberSystems.GoodSync','OpenVPNTechnologies.OpenVPN')

    # Aplicando bloqueio (pin)
    Show-Header -Text "Aplicando bloqueio (pin) nos programas da blacklist..." -Color $Yellow
    foreach ($id in $blacklistedIds) {
        try {
            if (winget list --id $id 2>$null) {
                winget pin add --id $id --blocking --force --accept-source-agreements 2>$null | Out-Null
                Write-Host "- A atualização deste programa foi bloqueada: $id"
            } else {
                Write-Host "⚠ programa $id não encontrado. Pin ignorado." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "✖ Falha ao aplicar pin em $id" -ForegroundColor Red
        }
    }

    # Verificando programas com atualização disponível
    Show-Header -Text "Verificando programas com atualização disponível..." -Color $Cyan
    $updatesRaw = winget upgrade --source winget --accept-source-agreements | Out-String
    $updates = @()

    foreach ($line in ($updatesRaw -split "`n")) {
        $parts = $line -split '\s{2,}'
        if ($parts.Count -ge 3 -and $parts[0] -notmatch 'Id|^-+$' -and $parts[0].Trim() -ne '') {
            $updates += [PSCustomObject]@{
                Id      = $parts[0].Trim()
                Nome    = $parts[1].Trim()
                Versao  = $parts[2].Trim()
            }
        }
    }

    if ($updates.Count -eq 0) {
        Show-Header -Text "Nenhum programa com atualização disponível." -Color $Yellow
        Write-Log 'Nenhum programa com atualização disponível.' 'WARN'
        return
    }

    # Filtra programas não bloqueados
    $permitidos = $updates | Where-Object { $blacklistedIds -notcontains $_.Id }

    if (-not $permitidos -or $permitidos.Count -eq 0) {
        Show-Header -Text "Nenhum programa permitido para atualização." -Color $Yellow
        Write-Log 'Nenhum programa permitido para atualização.' 'WARN'
        return
    }

    # Atualizando programas permitidos
    Show-Header -Text "Atualizando programas permitidos..." -Color $Cyan
    $atualizados = @()
    foreach ($pkg in $permitidos) {
        if ($pkg.Id -and $pkg.Id -ne '-') {
            try {
                Write-Host "→ Atualizando: $($pkg.Nome)" -ForegroundColor Cyan
                winget upgrade --id $pkg.Id --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
                $atualizados += $pkg.Nome
            } catch {
                Write-Host "✖ Falha ao atualizar: $($pkg.Nome)" -ForegroundColor Red
            }
        }
    }

    # Resumo final
    Show-Header -Text "Atualização concluída!" -Color $Green
    Show-Header -Text "programas atualizados: $($atualizados -join ', ')" -Color $Cyan
    Show-Header -Text "programas bloqueados: $($blacklistedIds -join ', ')" -Color $Yellow
    Write-Log ("Atualização concluída. Programas atualizados: {0}" -f ($atualizados -join ', ')) 'INFO'
    Write-Log ("Programas bloqueados: {0}" -f ($blacklistedIds -join ', ')) 'INFO'
}
