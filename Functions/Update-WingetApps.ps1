
function Update-WingetApps {
    [CmdletBinding()]
    param()

    Show-Header -Text "Iniciando atualização completa via Winget (exceto blacklist)..." -Color $Cyan
    Write-Log 'Iniciando atualização completa via Winget (exceto blacklist)...' 'INFO'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Show-Header -Text "Winget não está disponível. Etapa ignorada." -Color $Yellow
        return
    }

    # Blacklist
    $blacklistedIds = @('QGIS.QGIS','TeamViewer.TeamViewer','SiberSystems.GoodSync','OpenVPNTechnologies.OpenVPN')

    Show-Header -Text "Aplicando bloqueio (pin) nos programas da blacklist..." -Color $Yellow
    foreach ($id in $blacklistedIds) {
        try {
            if (winget list --id $id 2>$null) {
                winget pin add --id $id --blocking --force --accept-source-agreements 2>$null | Out-Null
                Write-Host "- Bloqueado: $id"
            }
        } catch {
            Write-Host "✖ Falha ao aplicar pin em $id" -ForegroundColor Red
        }
    }

    Show-Header -Text "Atualizando todos os programas permitidos..." -Color $Cyan
    try {
        # Atualiza tudo, exceto os bloqueados
        winget upgrade --all --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        Show-Header -Text "✅ Atualização concluída com sucesso!" -Color $Green
    } catch {
        Show-Header -Text "✖ Falha ao executar atualização completa." -Color $Red
    }

    Show-Header -Text "Programas bloqueados: $($blacklistedIds -join ', ')" -Color $Yellow
}
