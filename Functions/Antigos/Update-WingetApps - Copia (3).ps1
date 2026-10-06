function Update-WingetApps {
    [CmdletBinding()]
    param([switch]$AtualizarUsuario)

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
                "--source",
                "winget",
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
        # 7. ATUALIZACOES NO CONTEXTO DO USUARIO INTERATIVO
        # ============================================================
        $userStatus = 'Pendente'
        $userExitCode = 1
        $taskName = $null
        $taskCreated = $false
        $resultFile = $null

        if ($AtualizarUsuario) {
        try {
            $consoleUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
            if ([string]::IsNullOrWhiteSpace($consoleUser)) {
                $userStatus = 'Sem usuario interativo; atualizacao por usuario pendente'
                Write-Log $userStatus 'WARN'
            }
            else {
                $sid = ([System.Security.Principal.NTAccount]$consoleUser).Translate(
                    [System.Security.Principal.SecurityIdentifier]).Value
                $profileKey = Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop
                $profile = [Environment]::ExpandEnvironmentVariables($profileKey.ProfileImagePath)
                $userTemp = Join-Path $profile 'AppData\Local\Temp'
                if (-not (Test-Path -LiteralPath $userTemp -PathType Container)) {
                    throw 'Pasta temporaria do usuario indisponivel.'
                }

                $taskName = 'Guardian-WingetUser-' + [guid]::NewGuid().ToString('N')
                $resultFile = Join-Path $userTemp ($taskName + '.exitcode')
                $quotedResult = "'" + $resultFile.Replace("'", "''") + "'"
                # MS Store (inclui aplicativos MSIX/AppX por usuario) e pacotes
                # winget instalados no escopo do usuario. Sem elevacao de privilegios.
                $command = @'
$ErrorActionPreference = 'Stop'
$codes = @()
try {
    winget.exe upgrade --all --source msstore --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    $codes += [int]$LASTEXITCODE
    winget.exe upgrade --all --source winget --scope user --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    $codes += [int]$LASTEXITCODE
} catch { $codes += 1 }
$final = if (@($codes | Where-Object { $_ -ne 0 }).Count -gt 0) { 1 } else { 0 }
[System.IO.File]::WriteAllText(__RESULT__, [string]$final)
'@
                $command = $command.Replace('__RESULT__', $quotedResult)
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
                $pwsh = (Get-Process -Id $PID -ErrorAction Stop).Path
                $action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -EncodedCommand $encoded"
                $principal = New-ScheduledTaskPrincipal -UserId $consoleUser -LogonType Interactive -RunLevel Limited
                $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
                $taskCreated = $true
                Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
                $deadline = (Get-Date).AddMinutes(5)
                while (-not (Test-Path -LiteralPath $resultFile) -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 2
                    $state = (Get-ScheduledTask -TaskName $taskName -ErrorAction Stop).State
                    if ($state -notin @('Running', 'Queued', 'Ready')) { break }
                }
                if (Test-Path -LiteralPath $resultFile) {
                    $userExitCode = [int](Get-Content -LiteralPath $resultFile -Raw -ErrorAction Stop).Trim()
                    $userStatus = if ($userExitCode -eq 0) { 'OK' } else { 'Atualizacoes por usuario com falhas' }
                } else {
                    $userStatus = 'Sem resultado ou tempo limite atingido'
                }
                Write-Log "Winget usuario ($consoleUser): $userStatus" $(if ($userExitCode -eq 0) { 'INFO' } else { 'WARN' })
            }
        }
        catch {
            $userStatus = "Falha: $_"
            Write-Log "Winget usuario: $userStatus" 'WARN'
        }
        finally {
            if ($taskCreated) {
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($resultFile) { Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue }
        }

        } else {
            $userExitCode = 0
            $userStatus = 'Dispensado (RodaGuardian)'
        }

        # ============================================================
        # 7. RESULTADO
        # ============================================================

        if ($process.ExitCode -eq 0 -and $userExitCode -ne 0) {
            Write-Log "Winget administrativo OK; usuario: $userStatus" 'WARN'
            return [PSCustomObject]@{
                MensagemTecnica = "Winget administrativo OK; usuario: $userStatus"
                ExitCode        = 1
            }
        }

        switch ($process.ExitCode) {

            0 {

                Write-Log `
                    "Winget finalizado com sucesso." `
                    "INFO"

                return [PSCustomObject]@{
                    MensagemTecnica = "Winget administrativo e usuario finalizados com sucesso."
                    ExitCode        = 0
                }
            }

            default {

                Write-Log `
                    "Winget terminou com erro. ExitCode=$($process.ExitCode)." `
                    "ERROR"

                return [PSCustomObject]@{
                    MensagemTecnica = "Winget administrativo terminou com erro. ExitCode=$($process.ExitCode). Usuario: $userStatus"
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