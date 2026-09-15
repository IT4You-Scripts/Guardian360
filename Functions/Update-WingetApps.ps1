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
        # 2. ARGUMENTOS UTILIZADOS PELO WINGET
        # ============================================================

        $sourceArgs = @(
            "source",
            "update",
            "--disable-interactivity"
        )

        $wingetArgs = @(
            "upgrade",
            "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--silent",
            "--disable-interactivity"
        )


        # ============================================================
        # 3. ATUALIZAR AS FONTES DO WINGET
        # ============================================================

        Write-Host "- Verificando fontes do Winget..."

        Write-Log `
            "Atualizando fontes do Winget." `
            "INFO"

        $sourceProcess = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList $sourceArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Log `
            "Winget source update retornou ExitCode=$($sourceProcess.ExitCode)." `
            "INFO"


        # ============================================================
        # 4. SE SOURCE UPDATE FALHOU, RESETAR AS FONTES
        # ============================================================

        if ($sourceProcess.ExitCode -ne 0) {

            Write-Host ""

            Show-Header `
                -Text "Fontes do Winget precisam ser reparadas." `
                -Color $Yellow

            Write-Log `
                "Source update falhou. Tentando source reset --force." `
                "WARN"

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


            # Tenta atualizar novamente após o reset
            $sourceProcess = Start-Process `
                -FilePath $wingetExe `
                -ArgumentList $sourceArgs `
                -NoNewWindow `
                -Wait `
                -PassThru

            Write-Log `
                "Source update após reset retornou ExitCode=$($sourceProcess.ExitCode)." `
                "INFO"
        }


        # ============================================================
        # 5. PRIMEIRA TENTATIVA DE ATUALIZAÇÃO
        # ============================================================

        Write-Host ""
        Write-Host "- Atualizando aplicativos via Winget..."

        Write-Log `
            "Iniciando atualização de aplicativos via Winget." `
            "INFO"

        $process = Start-Process `
            -FilePath $wingetExe `
            -ArgumentList $wingetArgs `
            -NoNewWindow `
            -Wait `
            -PassThru

        Write-Log `
            "Primeira execução do Winget retornou ExitCode=$($process.ExitCode)." `
            "INFO"


        # ============================================================
        # 6. SE O UPGRADE FALHOU, REPARAR MICROSOFT.WINGET.SOURCE
        # ============================================================

        if ($process.ExitCode -ne 0) {

            Write-Host ""

            Show-Header `
                -Text "Winget apresentou erro. Tentando reparar a origem..." `
                -Color $Yellow

            Write-Log `
                "Winget falhou com ExitCode=$($process.ExitCode). Tentando reparar Microsoft.Winget.Source." `
                "WARN"

            try {

                # ====================================================
                # 6.1 LOCALIZAR O MANIFESTO DA SOURCE
                # ====================================================

                $sourceManifest = Get-ChildItem `
                    "C:\Program Files\WindowsApps\Microsoft.Winget.Source_*\AppXManifest.xml" `
                    -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName

                if (-not $sourceManifest) {

                    throw "Manifesto Microsoft.Winget.Source não encontrado."
                }

                Write-Host "- Registrando novamente Microsoft.Winget.Source..."

                Write-Log `
                    "Manifesto encontrado: $sourceManifest" `
                    "INFO"


                # ====================================================
                # 6.2 USAR WINDOWS POWERSHELL 5.1 PARA ADD-APPXPACKAGE
                #
                # O Guardian roda no PowerShell 7.
                # O módulo Appx/Add-AppxPackage será executado
                # separadamente pelo Windows PowerShell 5.1.
                # ====================================================

                $windowsPowerShell = `
                    "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

                if (-not (Test-Path $windowsPowerShell)) {
                    throw "Windows PowerShell 5.1 não encontrado em $windowsPowerShell"
                }

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

                if ($registerProcess.ExitCode -ne 0) {

                    throw `
                        "Windows PowerShell não conseguiu registrar Microsoft.Winget.Source. ExitCode=$($registerProcess.ExitCode)"
                }

                Write-Log `
                    "Microsoft.Winget.Source registrado novamente via Windows PowerShell 5.1." `
                    "INFO"


                # ====================================================
                # 6.3 RESETAR AS SOURCES APÓS O REGISTRO
                # ====================================================

                Write-Host "- Reconstruindo fontes do Winget..."

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
                    "Source reset após registro retornou ExitCode=$($resetProcess.ExitCode)." `
                    "INFO"


                # ====================================================
                # 6.4 ATUALIZAR AS SOURCES NOVAMENTE
                # ====================================================

                Write-Host "- Atualizando fontes após o reparo..."

                $repairSource = Start-Process `
                    -FilePath $wingetExe `
                    -ArgumentList $sourceArgs `
                    -NoNewWindow `
                    -Wait `
                    -PassThru

                Write-Log `
                    "Source update após reparo retornou ExitCode=$($repairSource.ExitCode)." `
                    "INFO"


                # ====================================================
                # 6.5 SEGUNDA TENTATIVA DO UPGRADE
                # ====================================================

                Write-Host ""
                Write-Host "- Tentando novamente a atualização via Winget..."

                Write-Log `
                    "Executando segunda tentativa de atualização via Winget." `
                    "INFO"

                $process = Start-Process `
                    -FilePath $wingetExe `
                    -ArgumentList $wingetArgs `
                    -NoNewWindow `
                    -Wait `
                    -PassThru

                Write-Log `
                    "Segunda execução do Winget retornou ExitCode=$($process.ExitCode)." `
                    "INFO"
            }
            catch {

                Show-Header `
                    -Text "Falha ao reparar Microsoft.Winget.Source: $_" `
                    -Color $Red

                Write-Log `
                    ("Falha ao reparar Microsoft.Winget.Source: {0}" -f $_) `
                    "ERROR"
            }
        }


        # ============================================================
        # 7. RESULTADO FINAL
        # ============================================================

        Write-Host ""

        if ($process.ExitCode -ne 0) {

            Show-Header `
                -Text "Winget terminou com código $($process.ExitCode)." `
                -Color $Yellow

            Write-Log `
                "Winget terminou com código inesperado: $($process.ExitCode)" `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = `
                    "Winget terminou com erro. ExitCode=$($process.ExitCode)"

                ExitCode = $process.ExitCode
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