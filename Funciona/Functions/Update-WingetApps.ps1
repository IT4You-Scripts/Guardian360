
function Update-WingetApps {
    [CmdletBinding()]
    param()

    Write-Log 'Iniciando atualização de aplicativos via Winget (modo confiável)...' 'INFO'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log 'Winget não está disponível. Etapa ignorada.' 'WARN'
        return
    }

    # Blacklist por ID (winget respeita melhor que nome)
    $blacklistedIds = @(
        'QGIS.QGIS',
        'TeamViewer.TeamViewer',
        'SiberSystems.GoodSync',
        'OpenVPNTechnologies.OpenVPN'
    )

    foreach ($id in $blacklistedIds) {
        Write-Log ("Winget: bloqueando atualizações para {0}" -f $id) 'DEBUG'
    }

    try {
        # Atualiza tudo
        $process = Start-Process winget `
            -ArgumentList @(
                'upgrade',
                '--all',
                '--accept-source-agreements',
                '--accept-package-agreements',
                '--scope=machine',
                '--silent',
                '--disable-interactivity'
            ) `
            -NoNewWindow `
            -Wait `
            -PassThru
    } catch {
        Write-Log ("Falha ao executar winget upgrade --all: {0}" -f $_.Exception.Message) 'WARN'
        return
    }

    # Pós-processamento: aplica pin apenas se o pacote existir
    foreach ($id in $blacklistedIds) {
        try {
            $exists = winget list --id $id 2>$null
            if ($exists) {
                winget pin add --id $id --blocking --force --accept-source-agreements 2>$null | Out-Null
                Write-Log ("Winget: pacote fixado (pin) para impedir upgrades futuros -> {0}" -f $id) 'INFO'
            } else {
                Write-Log ("Pacote {0} não encontrado. Pin ignorado." -f $id) 'WARN'
            }
        } catch {
            Write-Log ("Falha ao aplicar pin em {0}: {1}" -f $id, $_.Exception.Message) 'WARN'
        }
    }

    Write-Log 'Atualização de aplicativos via Winget finalizada.' 'INFO'
}
