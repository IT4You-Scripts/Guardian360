function Update-WingetApps {
    [CmdletBinding()]
    param()

    Write-Host ""

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Show-Header -Text "Winget não está disponível. Etapa ignorada." -Color $Yellow
        return
    }

    Write-Host "-Atualizando aplicativos via Winget..."

    try {
        $wingetArgs = @(
            "upgrade", "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--silent",
            "--disable-interactivity"
        )

        $process = Start-Process winget -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
        Write-Host ""

        if ($process.ExitCode -eq 0) {
            #Show-Header -Text "Winget concluído com sucesso." -Color $Green
        }
        else {
            Show-Header -Text "Winget terminou com código $($process.ExitCode)." -Color $Yellow
        }

    } catch {
        Show-Header -Text "Falha ao executar atualização completa: $_" -Color $Red
    }
}
