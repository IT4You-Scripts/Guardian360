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

            Show-Header -Text "Winget não está disponível. Phase ignorada." -Color $Yellow
            Write-Log "Winget não encontrado. Phase ignorada." "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget não encontrado. Phase ignorada."
                ExitCode        = $null
            }
        }

        Write-Log "Winget localizado em: $wingetExe" "INFO"


        # ============================================================
        # 2. VERIFICAR / ATUALIZAR AS SOURCES
        # ============================================================

        Write-Host "- Verificando fontes do Winget..."
        Write-Log "Verificando/atualizando fontes do Winget." "INFO"

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


        # ============================================================
        # 3. SE SOURCE UPDATE FALHOU, RECONSTRUIR AS SOURCES
        # ============================================================

        if ($sourceProcess.ExitCode -ne 0) {

            Write-Host ""
            Show-Header -Text "Fontes do Winget precisam ser reparadas." -Color $Yellow

            Write-Log `
                "Winget source update falhou com ExitCode=$($sourceProcess.ExitCode). Tentando reset." `
                "WARN"

            $resetArgs = @(
                "source",
                "reset",
                "--force"
            )

            $resetProcess = Start-Process `
                -FilePath $wingetExe `
                -ArgumentList $resetArgs `
                -NoNewWindow `
                -Wait `
                -PassThru

            if ($resetProcess.ExitCode -ne 0) {

                Show-Header `
                    -Text "Não foi possível reconstruir as fontes do Winget. Código $($resetProcess.ExitCode)." `
                    -Color $Red

                Write-Log `
                    "Winget source reset falhou. ExitCode=$($resetProcess.ExitCode)" `
                    "ERROR"

                return [PSCustomObject]@{
                    MensagemTecnica = "Falha ao reconstruir fontes do Winget. ExitCode=$($resetProcess.ExitCode)"
                    ExitCode        = $resetProcess.ExitCode
                }
            }


            # ========================================================
            # 4. ATUALIZAR NOVAMENTE APÓS O RESET
            # ========================================================

            Write-Host "- Atualizando novamente as fontes do Winget..."
            Write-Log "Executando source update após reset." "INFO"

            $sourceProcess = Start-Process `
                -FilePath $wingetExe `
                -ArgumentList $sourceArgs `
                -NoNewWindow `
                -Wait `
                -PassThru

            if ($sourceProcess.ExitCode -ne 0) {

                Show-Header `
                    -Text "As fontes do Winget continuam indisponíveis. Código $($sourceProcess.ExitCode)." `
                    -Color $Red

                Write-Log `
                    "Winget source update continuou falhando após reset. ExitCode=$($sourceProcess.ExitCode)" `
                    "ERROR"

                return [PSCustomObject]@{
                    MensagemTecnica = "Falha nas fontes do Winget após reset. ExitCode=$($sourceProcess.ExitCode)"
                    ExitCode        = $sourceProcess.ExitCode
                }
            }
        }


        # ============================================================
        # 5. EXECUTAR ATUALIZAÇÃO DOS PROGRAMAS
        # ============================================================

        Write-Host ""
        Write-Host "- Atualizando aplicativos via Winget..."
        Write-Log "Iniciando atualização de aplicativos via Winget." "INFO"

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
        # 6. VERIFICAR RESULTADO
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