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

        # Se não encontrou, procura o executável real no WindowsApps
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

            Show-Header -Text "Winget não está disponível. Fase ignorada." -Color $Yellow
            Write-Log "Winget não encontrado. Fase ignorada." "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget não encontrado. Fase ignorada."
                ExitCode        = $null
            }
        }

        Write-Log "Winget localizado em: $wingetExe" "INFO"


        # ============================================================
        # 2. ATUALIZAR AS FONTES DO WINGET
        # ============================================================

        Write-Host "- Verificando fontes do Winget..."
        Write-Log "Atualizando fontes do Winget." "INFO"

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


        # ============================================================
        # 3. SE SOURCE UPDATE FALHOU, RESETAR AS FONTES
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

            # Tenta atualizar novamente
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
        # 4. PREPARAR ATUALIZAÇÃO DOS PROGRAMAS
        # ============================================================

        $wingetArgs = @(
            "upgrade",
            "--all",
            "--accept-source-agreements",
            "--accept-package-agreements",
            "--silent",
            "--disable-interactivity"
        )

        Write-Host ""
        Write-Host "- Atualizando aplicativos via Winget..."
        Write-Log "Iniciando atualização de aplicativos via Winget." "INFO"


        # ============================================================
        # 5. PRIMEIRA TENTATIVA
        # ============================================================

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
        # 6. SE FALHOU, REPARAR MICROSOFT.WINGET.SOURCE
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

                # Localiza o manifesto mais recente da source
                $sourceManifest = Get-ChildItem `
                    "C:\Program Files\WindowsApps\Microsoft.Winget.Source_*\AppXManifest.xml" `
                    -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName

                if ($sourceManifest) {

                    Write-Host "- Registrando novamente Microsoft.Winget.Source..."

                    Write-Log `
                        "Manifesto encontrado: $sourceManifest" `
                        "INFO"

                    Add-AppxPackage `
                        -DisableDevelopmentMode `
                        -Register $sourceManifest `
                        -ErrorAction Stop

                    Write-Log `
                        "Microsoft.Winget.Source registrado novamente." `
                        "INFO"


                    # ====================================================
                    # 7. RESETAR SOURCES APÓS REGISTRAR O PACOTE
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
                    # 8. ATUALIZAR SOURCES NOVAMENTE
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
                    # 9. SEGUNDA TENTATIVA DO UPGRADE
                    # ====================================================

                    Write-Host ""
                    Write-Host "- Tentando novamente a atualização via Winget..."

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
                else {

                    Write-Log `
                        "Manifesto Microsoft.Winget.Source não encontrado." `
                        "ERROR"

                    Show-Header `
                        -Text "Pacote Microsoft.Winget.Source não encontrado." `
                        -Color $Red
                }
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
        # 10. RESULTADO FINAL
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
                MensagemTecnica = "Winget terminou com erro. ExitCode=$($process.ExitCode)"
                ExitCode        = $process.ExitCode
            }
        }

        Write-Log "Winget finalizado com sucesso." "INFO"

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