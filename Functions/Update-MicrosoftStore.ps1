function Update-MicrosoftStore {
    [CmdletBinding()]
    param()

    Write-Log 'Iniciando atualização da Microsoft Store...' 'INFO'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log 'Winget não está disponível. Etapa ignorada.' 'WARN'
        return
    }

    try {
        $proc = Start-Process winget `
            -ArgumentList @(
                'upgrade',
                '--source', 'msstore',
                '--accept-source-agreements',
                '--accept-package-agreements',
                '--silent',
                '--disable-interactivity'
            ) `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    }
    catch {
        Write-Log ("Falha ao iniciar winget (Microsoft Store): {0}" -f $_.Exception.Message) 'WARN'
        return
    }

    # Exit codes conhecidos do winget/msstore
    $acceptedExitCodes = @(
        0,              # Sucesso real
        -1978335210     # 0x8A150036 → nada a atualizar / estado OK
    )

    if ($proc.ExitCode -notin $acceptedExitCodes) {
        Write-Log ("Winget retornou erro inesperado ao atualizar Microsoft Store. ExitCode={0}" -f $proc.ExitCode) 'WARN'
        return
    }

    Write-Log 'Atualização da Microsoft Store concluída.' 'INFO'
}
