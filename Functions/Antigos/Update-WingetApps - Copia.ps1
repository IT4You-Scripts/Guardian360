function Update-WingetApps {
    [CmdletBinding()]
    param()

    Write-Host ""

    try {

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {

            Show-Header -Text "Winget não está disponível. Phase ignorada." -Color $Yellow
            Write-Log "Winget não encontrado. Phase ignorada." "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget não encontrado. Phase ignorada."
                ExitCode        = $null
            }
        }

        Write-Host "- Atualizando aplicativos via Winget..."
        Write-Log  "Iniciando atualização de aplicativos via Winget." "INFO"

        $wingetArgs = @(
            "upgrade", "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--silent",
            "--disable-interactivity"
        )

        $process = Start-Process winget `
            -ArgumentList $wingetArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Host ""

        if ($process.ExitCode -ne 0) {

            Show-Header -Text "Winget terminou com código $($process.ExitCode)." -Color $Yellow
            Write-Log ("Winget terminou com código inesperado: {0}" -f $process.ExitCode) "WARN"
        }

        Write-Log "Winget finalizado." "INFO"

        return [PSCustomObject]@{
            MensagemTecnica = "Winget finalizado. ExitCode=$($process.ExitCode)"
            ExitCode        = $process.ExitCode
        }
    }
    catch {

        Show-Header -Text "Falha ao executar atualização completa: $_" -Color $Red
        Write-Log ("Falha ao executar atualização completa: {0}" -f $_) "ERROR"

        throw
    }
}
