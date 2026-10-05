function Update-WingetApps {
    [CmdletBinding()]
    param()

    Write-Host ""

    try {

        # ============================================================
        # 1. LOCALIZAR O WINGET
        # ============================================================

        $wingetExe = $null

        $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue

        if ($wingetCommand) {
            $wingetExe = $wingetCommand.Source
        }

        if (-not $wingetExe) {

            $wingetExe = Get-ChildItem `
                "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 0 } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $wingetExe) {

            Show-Header `
                -Text "Winget não está disponível. Fase ignorada." `
                -Color $Yellow

            Write-Log `
                "Winget não encontrado. Fase ignorada." `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget não encontrado."
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
        # 3. TENTAR REGISTRAR MICROSOFT.WINGET.SOURCE
        # ============================================================

        if ($sourceManifest) {

            try {

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

                    Write-Log `
                        "Registro Microsoft.Winget.Source retornou ExitCode=$($registerProcess.ExitCode)." `
                        "INFO"
                }

            }
            catch {

                Write-Log `
                    ("Falha ao registrar Microsoft.Winget.Source: {0}" -f $_) `
                    "WARN"
            }
        }


        # ============================================================
        # 4. RECONSTRUIR FONTES (NÃO FATAL)
        # ============================================================

        try {

            Write-Host "- Verificando fontes do Winget..."
            Write-Log "Executando source reset." "INFO"

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

        }
        catch {

            Write-Log `
                ("Falha em source reset: {0}" -f $_) `
                "WARN"
        }


        # ============================================================
        # 5. ATUALIZAR FONTES (NÃO FATAL)
        # ============================================================

        try {

            $sourceProcess = Start-Process `
                -FilePath $wingetExe `
                -ArgumentList @(
                    "source",
                    "update",
                    "--disable-interactivity"
                ) `
                -NoNewWindow `
                -Wait `
                -PassThru

            Write-Log `
                "Winget source update retornou ExitCode=$($sourceProcess.ExitCode)." `
                "INFO"

            if ($sourceProcess.ExitCode -ne 0) {

                Write-Log `
                    "Source update falhou. Continuando mesmo assim." `
                    "WARN"
            }
        }
        catch {

            Write-Log `
                ("Erro durante source update: {0}" -f $_) `
                "WARN"
        }


        # ============================================================
        # 6. UPGRADE
        # ============================================================

        Write-Host ""
        Write-Host "- Atualizando aplicativos via Winget..."

        Write-Log `
            "Iniciando atualização de aplicativos." `
            "INFO"

        $process = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList @(
                "upgrade",
                "--all",
                "--silent",
                "--disable-interactivity",
                "--accept-package-agreements",
                "--accept-source-agreements"
            ) `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Host ""

        Write-Log `
            "Winget upgrade retornou ExitCode=$($process.ExitCode)." `
            "INFO"


        # ============================================================
        # 7. RESULTADO
        # ============================================================

        switch ($process.ExitCode) {

            0 {

                Write-Log `
                    "Winget finalizado com sucesso." `
                    "INFO"

                return [PSCustomObject]@{
                    MensagemTecnica = "Winget finalizado com sucesso."
                    ExitCode        = 0
                }
            }

            default {

                Write-Log `
                    "Winget terminou com ExitCode=$($process.ExitCode). Algumas atualizações podem ter sido concluídas." `
                    "WARN"

                return [PSCustomObject]@{
                    MensagemTecnica = "Winget finalizado com sucesso parcial. ExitCode=$($process.ExitCode)"
                    ExitCode        = $process.ExitCode
                }
            }
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