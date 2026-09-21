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
        # 6. IDENTIFICAR APLICATIVOS COM ATUALIZAÇÃO
        # ============================================================

        Write-Host ""
        Write-Host "- Verificando aplicativos com atualização disponível..."

        Write-Log `
            "Consultando aplicativos com atualização disponível via Winget." `
            "INFO"

        # Usa saída JSON do próprio Winget para não depender da
        # formatação visual/idioma da tabela exibida no console.
        $upgradeJson = & $wingetExe `
            upgrade `
            --source winget `
            --accept-source-agreements `
            --disable-interactivity `
            --output json 2>$null

        $jsonExitCode = $LASTEXITCODE

        if ($jsonExitCode -ne 0 -or -not $upgradeJson) {

            Show-Header `
                -Text "Não foi possível obter a lista de atualizações do Winget." `
                -Color $Yellow

            Write-Log `
                "Falha ao consultar atualizações do Winget. ExitCode=$jsonExitCode." `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Falha ao consultar atualizações do Winget. ExitCode=$jsonExitCode"
                ExitCode        = $jsonExitCode
            }
        }

        try {
            $upgradeData = ($upgradeJson -join "`n") | ConvertFrom-Json
        }
        catch {

            Show-Header `
                -Text "Não foi possível interpretar a lista de atualizações do Winget." `
                -Color $Yellow

            Write-Log `
                "Falha ao interpretar JSON retornado pelo Winget: $_" `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Falha ao interpretar lista de atualizações do Winget."
                ExitCode        = 1
            }
        }

        $packageIds = @()

        # O JSON do winget agrupa os pacotes por SourceDetails.
        foreach ($source in @($upgradeData.Sources)) {

            foreach ($package in @($source.Packages)) {

                if ($package.PackageIdentifier) {
                    $packageIds += [string]$package.PackageIdentifier
                }
            }
        }

        $packageIds = @(
            $packageIds |
            Where-Object { $_ } |
            Sort-Object -Unique
        )

        if ($packageIds.Count -eq 0) {

            Write-Host "- Nenhuma atualização disponível."

            Write-Log `
                "Nenhum aplicativo com atualização disponível." `
                "INFO"

            return [PSCustomObject]@{
                MensagemTecnica = "Nenhum aplicativo com atualização disponível."
                ExitCode        = 0
            }
        }

        Write-Host "- Encontradas $($packageIds.Count) atualização(ões)."
        Write-Host ""

        Write-Log `
            "Encontradas $($packageIds.Count) atualização(ões) via Winget." `
            "INFO"


        # ============================================================
        # 7. ATUALIZAR CADA APLICATIVO INDIVIDUALMENTE
        #
        # IMPORTANTE:
        # Um pacote com erro NÃO interrompe os demais.
        #
        # A chamada abaixo é propositalmente direta (&), igual ao
        # comando manual validado.
        # ============================================================

        $sucessos = 0
        $falhas   = 0

        foreach ($packageId in $packageIds) {

            Write-Host ""
            Write-Host "- Atualizando: $packageId"

            Write-Log `
                "Iniciando atualização individual: $packageId" `
                "INFO"

            & $wingetExe `
                upgrade `
                --id $packageId `
                --exact `
                --source winget `
                --accept-source-agreements `
                --accept-package-agreements `
                --silent `
                --disable-interactivity

            $packageExitCode = $LASTEXITCODE

            if ($packageExitCode -eq 0) {

                $sucessos++

                Write-Host "[OK] $packageId"

                Write-Log `
                    "Winget concluiu $packageId com ExitCode=0." `
                    "INFO"
            }
            else {

                $falhas++

                Write-Host `
                    "[AVISO] $packageId falhou. ExitCode=$packageExitCode"

                Write-Log `
                    "Falha ao atualizar $packageId. ExitCode=$packageExitCode. Continuando para o próximo aplicativo." `
                    "WARN"
            }
        }


        # ============================================================
        # 8. RESULTADO
        # ============================================================

        Write-Host ""
        Write-Host "- Winget finalizado. Sucessos: $sucessos | Falhas: $falhas"

        if ($falhas -gt 0) {

            Show-Header `
                -Text "Winget terminou com $falhas falha(s). Os demais aplicativos foram processados." `
                -Color $Yellow

            Write-Log `
                "Winget finalizado com falhas parciais. Sucessos=$sucessos; Falhas=$falhas." `
                "WARN"

            return [PSCustomObject]@{
                MensagemTecnica = "Winget finalizado com falhas parciais. Sucessos=$sucessos; Falhas=$falhas."
                ExitCode        = 1
            }
        }

        Write-Log `
            "Winget finalizado com sucesso. Aplicativos processados=$sucessos." `
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