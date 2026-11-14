function Update-WingetApps {
    [CmdletBinding()]
    param()

    Write-Host ""

    try {

        # ============================================================
        # 1. LOCALIZAR O WINGET
        # ============================================================

        $wingetExe = $null

        # Primeiro tenta localizar normalmente
        $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue

        if ($wingetCommand) {
            $wingetExe = $wingetCommand.Source
        }

        # Se não encontrou pelo PATH/Alias, procura o executável real
        if (-not $wingetExe) {

            $wingetExe = Get-ChildItem `
                "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 0 } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }

        # Winget realmente não existe
        if (-not $wingetExe) {

            Show-Header `
                -Text "Winget não está disponível. Fase ignorada." `
                -Color $Yellow

            Write-Log `
                "Winget não encontrado. Fase ignorada." `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget não encontrado. Fase ignorada."
                ExitCode        = $null
            }
        }

        Write-Log `
            "Winget localizado em: $wingetExe" `
            "INFO"


        # ============================================================
        # 2. LOCALIZAR MICROSOFT.WINGET.SOURCE
        # ============================================================

        $sourceManifest = Get-ChildItem `
            "C:\Program Files\WindowsApps\Microsoft.Winget.Source_*\AppXManifest.xml" `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName


        # ============================================================
        # 3. REGISTRAR MICROSOFT.WINGET.SOURCE
        #
        # O Guardian roda no PowerShell 7.
        # Add-AppxPackage precisa ser executado pelo
        # Windows PowerShell 5.1 neste ambiente.
        # ============================================================

        if ($sourceManifest) {

            Write-Host "- Preparando origem do Winget..."
            Write-Log "Preparando Microsoft.Winget.Source." "INFO"

            $windowsPowerShell = `
                "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

            if (Test-Path $windowsPowerShell) {

                $escapedManifest = $sourceManifest.Replace("'", "''")

                $registerCommand = `
                    "Add-AppxPackage -DisableDevelopmentMode -Register '$escapedManifest' -ErrorAction Stop"

                $registerProcess = Start-Process `
                    -FilePath $windowsPowerShell `
                    -ArgumentList @(
                        "-NoProfile",
                        "-NonInteractive",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-Command",
                        $registerCommand
                    ) `
                    -NoNewWindow `
                    -Wait `
                    -PassThru

                if ($registerProcess.ExitCode -eq 0) {

                    Write-Log `
                        "Microsoft.Winget.Source registrado via Windows PowerShell 5.1." `
                        "INFO"
                }
                else {

                    Write-Log `
                        "Registro de Microsoft.Winget.Source retornou ExitCode=$($registerProcess.ExitCode)." `
                        "WARN"
                }
            }
            else {

                Write-Log `
                    "Windows PowerShell 5.1 não encontrado." `
                    "WARN"
            }
        }
        else {

            Write-Log `
                "Manifesto Microsoft.Winget.Source não encontrado." `
                "WARN"
        }


        # ============================================================
        # 4. RECONSTRUIR AS FONTES
        # ============================================================

        Write-Host "- Verificando fontes do Winget..."
        Write-Log "Reconstruindo fontes do Winget." "INFO"

        $resetProcess = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList @(
                "source",
                "reset",
                "--force"
            ) `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Log `
            "Winget source reset retornou ExitCode=$($resetProcess.ExitCode)." `
            "INFO"


        # ============================================================
        # 5. ATUALIZAR AS FONTES
        # ============================================================

        $sourceArgs = @(
            "source",
            "update",
            "--disable-interactivity"
        )

        $sourceProcess = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList $sourceArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Log `
            "Winget source update retornou ExitCode=$($sourceProcess.ExitCode)." `
            "INFO"

        if ($sourceProcess.ExitCode -ne 0) {

            Show-Header `
                -Text "Não foi possível atualizar as fontes do Winget." `
                -Color $Yellow

            Write-Log `
                "Falha ao atualizar fontes do Winget. ExitCode=$($sourceProcess.ExitCode)." `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Falha ao atualizar fontes do Winget. ExitCode=$($sourceProcess.ExitCode)"
                ExitCode        = $sourceProcess.ExitCode
            }
        }


        # ============================================================
        # 6. ATUALIZAR OS PROGRAMAS
        # ============================================================

        Write-Host ""
        Write-Host "- Atualizando aplicativos via Winget..."

        Write-Log `
            "Iniciando atualização de aplicativos via Winget." `
            "INFO"

        $wingetArgs = @(
            "upgrade",
            "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--silent",
            "--disable-interactivity"
        )

        $process = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList $wingetArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Host ""


        # ============================================================
        # 7. RESULTADO
        # ============================================================

        if ($process.ExitCode -ne 0) {

            Show-Header `
                -Text "Winget terminou com código $($process.ExitCode)." `
                -Color $Yellow

            Write-Log `
                "Winget terminou com código inesperado: $($process.ExitCode)" `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget terminou com erro. ExitCode=$($process.ExitCode)"
                ExitCode        = $process.ExitCode
            }
        }

        Write-Log `
            "Winget finalizado com sucesso." `
            "INFO"

        return [PSCustomObject]@{
            MensagemTecnica = "Winget finalizado com sucesso. ExitCode=0"
            ExitCode        = 0
        }
    }
    catch {

        Show-Header `
            -Text "Falha ao executar atualização completa: $_" `
            -Color $Red

        Write-Log `
            ("Falha ao executar atualização completa: {0}" -f $_) `
            "ERROR"

        throw
    }
}