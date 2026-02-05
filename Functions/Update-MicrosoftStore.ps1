function Update-MicrosoftStore {
    [CmdletBinding()]
    param()

    Write-Host "Iniciando atualização da Microsoft Store..." -ForegroundColor Cyan
    Write-Log 'Iniciando atualização da Microsoft Store...' 'INFO'

    try {

        # Verifica se winget existe
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {

            Write-Host "Winget não está disponível. Phase ignorada." -ForegroundColor Yellow
            Write-Log 'Winget não está disponível. Phase ignorada.' 'WARN'

            throw "Winget indisponível. Phase ignorada."
        }

        # Executa atualização da Microsoft Store via winget
        $proc = Start-Process winget `
            -ArgumentList @(
                'upgrade',
                '--source','msstore',
                '--accept-source-agreements',
                '--accept-package-agreements',
                '--silent',
                '--disable-interactivity'
            ) `
            -WindowStyle Hidden `
            -Wait `
            -PassThru

        # Exit codes aceitáveis
        $acceptedExitCodes = @(
            0,
            -1978335210
        )

        if ($proc.ExitCode -notin $acceptedExitCodes) {

            Write-Host ("Winget retornou erro inesperado. ExitCode={0}" -f $proc.ExitCode) -ForegroundColor Yellow
            Write-Log ("Winget retornou erro inesperado ao atualizar Microsoft Store. ExitCode={0}" -f $proc.ExitCode) 'WARN'

            throw "ExitCode inesperado do winget: $($proc.ExitCode)"
        }

        Write-Host "Atualização da Microsoft Store concluída." -ForegroundColor Green
        Write-Log 'Atualização da Microsoft Store concluída.' 'INFO'

        return [PSCustomObject]@{
            MensagemTecnica = "Atualização da Microsoft Store concluída. ExitCode=$($proc.ExitCode)"
            ExitCode        = $proc.ExitCode
        }
    }
    catch {

        Write-Host "ERRO durante Update-MicrosoftStore: $_" -ForegroundColor Red
        Write-Log ("Falha ao iniciar winget (Microsoft Store): {0}" -f $_.Exception.Message) 'WARN'

        throw
    }
}
