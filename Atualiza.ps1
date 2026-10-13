# ============================================================================
# AUTOATUALIZACAO DO PROPRIO ATUALIZA.PS1
# A marcacao de relancamento impede qualquer possibilidade de loop:
# a instancia nova pula esta verificacao uma unica vez e segue o Atualiza normal.
# ============================================================================
if ($env:GUARDIAN_ATUALIZA_RELANCADO -ne "1") {
    try {
        $SelfBaseUrl = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main/Atualiza.ps1"
        $SelfPath    = "C:\Guardian\Atualiza.ps1"
        $SelfTemp    = "C:\Guardian\Guardian_Atualiza_$PID.ps1"
        $SelfNoCache = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmssfff')"

        Invoke-WebRequest `
            -Uri "$SelfBaseUrl$SelfNoCache" `
            -OutFile $SelfTemp `
            -UseBasicParsing `
            -Headers @{ "Cache-Control" = "no-cache" } `
            -ErrorAction Stop

        $RemoteHash = (Get-FileHash -LiteralPath $SelfTemp -Algorithm SHA256).Hash
        $LocalHash  = $null

        if (Test-Path -LiteralPath $SelfPath) {
            $LocalHash = (Get-FileHash -LiteralPath $SelfPath -Algorithm SHA256).Hash
        }

        if ($RemoteHash -ne $LocalHash) {
            if (-not (Test-Path -LiteralPath "C:\Guardian")) {
                New-Item -ItemType Directory -Path "C:\Guardian" -Force | Out-Null
            }

            if (Test-Path -LiteralPath $SelfPath) {
                attrib -R $SelfPath 2>$null
            }

            Copy-Item -LiteralPath $SelfTemp -Destination $SelfPath -Force

            $PwshSelf = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
            if (-not $PwshSelf) {
                $PwshSelf = "powershell.exe"
            }

            # O processo filho herda esta variavel e, portanto, NAO tenta
            # se autoatualizar novamente nesta mesma cadeia de execucao.
            $env:GUARDIAN_ATUALIZA_RELANCADO = "1"

            Start-Process `
                -FilePath $PwshSelf `
                -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", "`"$SelfPath`""
                )

            Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
            exit 0
        }

        Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
    }
    catch {
        if ($SelfTemp -and (Test-Path -LiteralPath $SelfTemp -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $SelfTemp -Force -ErrorAction SilentlyContinue
        }
        # Se a autoatualizacao falhar, preserva o comportamento original.
    }
}
else {
    # Remove a marcacao dentro da nova instancia e continua normalmente.
    Remove-Item Env:\GUARDIAN_ATUALIZA_RELANCADO -ErrorAction SilentlyContinue
}

function Update-GuardianFiles {

    $ErrorActionPreference = "Stop"
    $ProgressPreference   = "SilentlyContinue"

    # -------------------------------
    # Função para cabeçalho estilizado
    # -------------------------------
    function Show-Header {
        param(
            [string]$Text,
            [ConsoleColor]$Color = 'Cyan'
        )

        $bar = '─' * ($Text.Length + 2)
        Write-Host ""
        Write-Host ("┌$bar┐") -ForegroundColor $Color
        Write-Host ("│ $Text │") -ForegroundColor $Color
        Write-Host ("└$bar┘") -ForegroundColor $Color
        Write-Host ""
    }

    # -------------------------------
    # Função de falha controlada
    # -------------------------------
    function Fail {
        param ([string]$Message)
        Show-Header $Message -Color Red
        Write-Host "O script será encerrado em 5 segundos..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        exit 1
    }

    # Configurações
    $BaseUrl   = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main"
    $BasePath  = "C:\Guardian"

    # Cache busting permanente (ANTI GitHub RAW cache)
    $NoCache   = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Estrutura base (nunca apaga nada)
    $Folders = @(
        $BasePath,
        "$BasePath\Functions",
        "$BasePath\Assets\Images"
    )

    foreach ($Folder in $Folders) {
        if (-not (Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }
    }

    # -------------------------------
    # Lista de arquivos oficiais
    # -------------------------------
    $Files = @(
        @{ Url = "$BaseUrl/RodaGuardian.ps1";                        Path = "$BasePath\RodaGuardian.new" },
        @{ Url = "$BaseUrl/ElevaGuardian.ps1";                       Path = "$BasePath\ElevaGuardian.new" },
        @{ Url = "$BaseUrl/Functions/Update-GuardianFiles.ps1";      Path = "$BasePath\Functions\Update-GuardianFiles.new" },

        @{ Url = "$BaseUrl/Atualiza.ps1";                            Path = "$BasePath\Atualiza.ps1" },
        @{ Url = "$BaseUrl/CriaCredenciais.ps1";                     Path = "$BasePath\CriaCredenciais.ps1" },
        @{ Url = "$BaseUrl/Guardian.ps1";                            Path = "$BasePath\Guardian.ps1" },
        @{ Url = "$BaseUrl/Prepara.ps1";                             Path = "$BasePath\Prepara.ps1" },
        @{ Url = "$BaseUrl/Guardian-Ghost.ps1";                      Path = "$BasePath\Guardian-Ghost.ps1" },
        @{ Url = "$BaseUrl/Assets/Images/logotipo.png";              Path = "$BasePath\Assets\Images\logotipo.png" },
        @{ Url = "$BaseUrl/Assets/Images/guardian_bg.png";           Path = "$BasePath\Assets\Images\guardian_bg.png" },
        @{ Url = "$BaseUrl/Assets/Images/guardian_end_bg.png";       Path = "$BasePath\Assets\Images\guardian_end_bg.png" },
        @{ Url = "$BaseUrl/Functions/Block-AppUpdates.ps1";          Path = "$BasePath\Functions\Block-AppUpdates.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-AllRecycleBins.ps1";      Path = "$BasePath\Functions\Clear-AllRecycleBins.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-BrowserCache.ps1";        Path = "$BasePath\Functions\Clear-BrowserCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-RecentFilesHistory.ps1";  Path = "$BasePath\Functions\Clear-RecentFilesHistory.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-TempFiles.ps1";           Path = "$BasePath\Functions\Clear-TempFiles.ps1" },
        @{ Url = "$BaseUrl/Functions/Clear-WindowsUpdateCache.ps1";  Path = "$BasePath\Functions\Clear-WindowsUpdateCache.ps1" },
        @{ Url = "$BaseUrl/Functions/Confirm-MacriumBackup.ps1";     Path = "$BasePath\Functions\Confirm-MacriumBackup.ps1" },
        @{ Url = "$BaseUrl/Functions/Get-SystemInventory.ps1";       Path = "$BasePath\Functions\Get-SystemInventory.ps1" },
        @{ Url = "$BaseUrl/Functions/Manage-RustDesk.ps1";           Path = "$BasePath\Functions\Manage-RustDesk.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-HDD.ps1";              Path = "$BasePath\Functions\Optimize-HDD.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-JsonReport.ps1";       Path = "$BasePath\Functions\Optimize-JsonReport.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-NetworkSettings.ps1";  Path = "$BasePath\Functions\Optimize-NetworkSettings.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-PowerSettings.ps1";    Path = "$BasePath\Functions\Optimize-PowerSettings.ps1" },
        @{ Url = "$BaseUrl/Functions/Optimize-SSD.ps1";              Path = "$BasePath\Functions\Optimize-SSD.ps1" },
        @{ Url = "$BaseUrl/Functions/Remove-OldUpdateFiles.ps1";     Path = "$BasePath\Functions\Remove-OldUpdateFiles.ps1" },
        @{ Url = "$BaseUrl/Functions/Repair-SystemIntegrity.ps1";    Path = "$BasePath\Functions\Repair-SystemIntegrity.ps1" },
        @{ Url = "$BaseUrl/Functions/Scan-AntiMalware.ps1";          Path = "$BasePath\Functions\Scan-AntiMalware.ps1" },
        @{ Url = "$BaseUrl/Functions/Send-LogToServer.ps1";          Path = "$BasePath\Functions\Send-LogToServer.ps1" },
        @{ Url = "$BaseUrl/Functions/Show-GuardianEndUI.ps1";        Path = "$BasePath\Functions\Show-GuardianEndUI.ps1" },
        @{ Url = "$BaseUrl/Functions/Show-GuardianUI.ps1";           Path = "$BasePath\Functions\Show-GuardianUI.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-MicrosoftStore.ps1";     Path = "$BasePath\Functions\Update-MicrosoftStore.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-WindowsOS.ps1";          Path = "$BasePath\Functions\Update-WindowsOS.ps1" },
        @{ Url = "$BaseUrl/Functions/Update-WingetApps.ps1";         Path = "$BasePath\Functions\Update-WingetApps.ps1" },
        @{ Url = "$BaseUrl/Functions/Write-JsonResult.ps1";          Path = "$BasePath\Functions\Write-JsonResult.ps1" }
    )

    Show-Header "Baixando arquivos do Guardian 360..." -Color Yellow

    foreach ($File in $Files) {
        try {
            if (Test-Path $File.Path) {
                attrib -R $File.Path 2>$null
            }
        }
        catch {
            Write-Host "Aviso: Não foi possível mudar os atributos dos arquivos $($File.Path)" -ForegroundColor DarkYellow
        }
    }

    Show-Header "Atualizando Guardian 360..." -Color Cyan

    foreach ($File in $Files) {
        try {
            Invoke-WebRequest `
                -Uri "$($File.Url)$NoCache" `
                -OutFile $File.Path `
                -UseBasicParsing `
                -Headers @{ "Cache-Control"="no-cache" } `
                -ErrorAction Stop
        }
        catch {

            if ($File.Path -match "\.png$") {
                Write-Host "Aviso: Falha ao baixar imagem $($File.Path)" -ForegroundColor DarkYellow
                continue
            }

            Fail "Falha crítica ao atualizar: $($File.Path)"
        }
    }

# Atualização dos arquivos que estavam na memória
$AtomicTargets = @(
    @{ New = "$BasePath\RodaGuardian.new";                    Final = "$BasePath\RodaGuardian.ps1" },
    @{ New = "$BasePath\ElevaGuardian.new";                   Final = "$BasePath\ElevaGuardian.ps1" },
    @{ New = "$BasePath\Functions\Update-GuardianFiles.new";  Final = "$BasePath\Functions\Update-GuardianFiles.ps1" }
)

foreach ($item in $AtomicTargets) {

    $src = $item.New
    $dst = $item.Final

    if (-not (Test-Path $src)) {
        continue
    }

    try {

        if (Test-Path $dst) {
            try {
                Set-ItemProperty -Path $dst -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            }
            catch {}
        }

        Move-Item -Path $src -Destination $dst -Force -ErrorAction Stop
    }
    catch {
        Write-Host "Aviso: não foi possível atualizar $dst" -ForegroundColor DarkYellow
    }
}


    # =========================================================================
    # PADRONIZAÇÃO DAS TAREFAS NO AGENDADOR
    # Mesma lógica validada no RodaGuardian/Guardian v4.
    # =========================================================================
    try {
        $taskFolder = "\Guardian\"

        # ----- TASK DO GUARDIAN (dias 1-10, 12:00, ociosidade 10min, aguardar 2h) -----
        $guardianTasks = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                         Where-Object {
                             $_.TaskName -like "*Guardian*" -and
                             $_.TaskName -notlike "*Ghost*" -and
                             $_.TaskName -notlike "*System*" -and
                             $_.TaskName -notlike "*Silencioso*" -and
                             $_.TaskName -notlike "*Execução Silenciosa*" -and
                             $_.TaskName -notmatch '^\s*[23]\.\s'
                         }

        foreach ($task in $guardianTasks) {
            $xmlStr = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $taskFolder
            $xml = [xml]$xmlStr
            $ns = $xml.Task.NamespaceURI

            $oldTriggers = $xml.Task.SelectSingleNode("*[local-name()='Triggers']")
            if ($oldTriggers) { $xml.Task.RemoveChild($oldTriggers) | Out-Null }

            $newTriggers = $xml.CreateElement("Triggers", $ns)
            $calTrigger = $xml.CreateElement("CalendarTrigger", $ns)

            $startEl = $xml.CreateElement("StartBoundary", $ns)
            $startEl.InnerText = "2026-01-01T12:00:00"
            $calTrigger.AppendChild($startEl) | Out-Null

            $enabledEl = $xml.CreateElement("Enabled", $ns)
            $enabledEl.InnerText = "true"
            $calTrigger.AppendChild($enabledEl) | Out-Null

            $monthlyEl = $xml.CreateElement("ScheduleByMonth", $ns)

            $daysEl = $xml.CreateElement("DaysOfMonth", $ns)
            1..10 | ForEach-Object {
                $dayEl = $xml.CreateElement("Day", $ns)
                $dayEl.InnerText = $_
                $daysEl.AppendChild($dayEl) | Out-Null
            }
            $monthlyEl.AppendChild($daysEl) | Out-Null

            $monthsEl = $xml.CreateElement("Months", $ns)
            @("January","February","March","April","May","June","July","August","September","October","November","December") | ForEach-Object {
                $mEl = $xml.CreateElement($_, $ns)
                $monthsEl.AppendChild($mEl) | Out-Null
            }
            $monthlyEl.AppendChild($monthsEl) | Out-Null
            $calTrigger.AppendChild($monthlyEl) | Out-Null
            $newTriggers.AppendChild($calTrigger) | Out-Null

            $principals = $xml.Task.SelectSingleNode("*[local-name()='Principals']")
            $xml.Task.InsertBefore($newTriggers, $principals) | Out-Null

            $actionArgsNode = $xml.Task.SelectSingleNode("*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Arguments']")
            if ($actionArgsNode -and $actionArgsNode.InnerText -notmatch '(?i)(^|\s)-WindowStyle\s+Hidden(\s|$)') {
                $actionArgsNode.InnerText = "-WindowStyle Hidden " + $actionArgsNode.InnerText
            }

            $settingsNode = $xml.Task.SelectSingleNode("*[local-name()='Settings']")

            $hiddenNode = $settingsNode.SelectSingleNode("*[local-name()='Hidden']")
            if ($hiddenNode) { $hiddenNode.InnerText = "true" }
            else {
                $hiddenEl = $xml.CreateElement("Hidden", $ns)
                $hiddenEl.InnerText = "true"
                $settingsNode.AppendChild($hiddenEl) | Out-Null
            }

            $batteryNode = $settingsNode.SelectSingleNode("*[local-name()='DisallowStartIfOnBatteries']")
            if ($batteryNode) { $batteryNode.InnerText = "false" }
            else {
                $batteryEl = $xml.CreateElement("DisallowStartIfOnBatteries", $ns)
                $batteryEl.InnerText = "false"
                $settingsNode.AppendChild($batteryEl) | Out-Null
            }

            $roiNode = $settingsNode.SelectSingleNode("*[local-name()='RunOnlyIfIdle']")
            if ($roiNode) { $roiNode.InnerText = "true" }
            else {
                $roiEl = $xml.CreateElement("RunOnlyIfIdle", $ns); $roiEl.InnerText = "true"
                $settingsNode.AppendChild($roiEl) | Out-Null
            }

            $idleSettings = $settingsNode.SelectSingleNode("*[local-name()='IdleSettings']")
            if (-not $idleSettings) {
                $idleSettings = $xml.CreateElement("IdleSettings", $ns)
                $settingsNode.AppendChild($idleSettings) | Out-Null
            }
            foreach ($child in @($idleSettings.ChildNodes)) { $idleSettings.RemoveChild($child) | Out-Null }

            $durEl = $xml.CreateElement("Duration", $ns); $durEl.InnerText = "PT10M"
            $idleSettings.AppendChild($durEl) | Out-Null
            $waitEl = $xml.CreateElement("WaitTimeout", $ns); $waitEl.InnerText = "PT2H"
            $idleSettings.AppendChild($waitEl) | Out-Null
            $stopEl = $xml.CreateElement("StopOnIdleEnd", $ns); $stopEl.InnerText = "false"
            $idleSettings.AppendChild($stopEl) | Out-Null
            $restartEl = $xml.CreateElement("RestartOnIdle", $ns); $restartEl.InnerText = "false"
            $idleSettings.AppendChild($restartEl) | Out-Null

            $nomePrincipalNovo = if ($task.TaskName -like "1. *") { $task.TaskName } else { "1. $($task.TaskName)" }
            Register-ScheduledTask -TaskName $nomePrincipalNovo -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
            if ($task.TaskName -ne $nomePrincipalNovo) {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue
            }
            Write-Host "[Guardian] Task '$($task.TaskName)' padronizada: dias 1-10, 12:00." -ForegroundColor Green
        }

        # ----- TASK GUARDIAN SILENCIOSO (dias 11-20, 15:00) -----
        # Replica o XML da tarefa Principal para preservar identidade e configuracoes.
        $guardianPrincipal = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like '1. *Guardian*' -and $_.TaskName -notmatch 'Ghost|System|Silencios' } |
            Select-Object -First 1
        if ($guardianPrincipal) {
            try {
                $silXml = [xml](Export-ScheduledTask -TaskName $guardianPrincipal.TaskName -TaskPath $taskFolder)
                $ns = $silXml.Task.NamespaceURI
                $triggers = $silXml.Task.SelectSingleNode("*[local-name()='Triggers']")
                if ($triggers) { $silXml.Task.RemoveChild($triggers) | Out-Null }
                $triggers = $silXml.CreateElement('Triggers',$ns)
                $cal = $silXml.CreateElement('CalendarTrigger',$ns)
                $startEl = $silXml.CreateElement('StartBoundary',$ns)
                $startEl.InnerText = '2026-01-11T15:00:00'
                $cal.AppendChild($startEl) | Out-Null
                $enabledEl = $silXml.CreateElement('Enabled',$ns)
                $enabledEl.InnerText = 'true'
                $cal.AppendChild($enabledEl) | Out-Null
                $monthly = $silXml.CreateElement('ScheduleByMonth',$ns)
                $days = $silXml.CreateElement('DaysOfMonth',$ns)
                11..20 | ForEach-Object { $day = $silXml.CreateElement('Day',$ns); $day.InnerText = [string]$_; $days.AppendChild($day) | Out-Null }
                $monthly.AppendChild($days) | Out-Null
                $months = $silXml.CreateElement('Months',$ns)
                @('January','February','March','April','May','June','July','August','September','October','November','December') | ForEach-Object {
                    $month = $silXml.CreateElement($_,$ns); $months.AppendChild($month) | Out-Null
                }
                $monthly.AppendChild($months) | Out-Null
                $cal.AppendChild($monthly) | Out-Null
                $triggers.AppendChild($cal) | Out-Null
                $principals = $silXml.Task.SelectSingleNode("*[local-name()='Principals']")
                $silXml.Task.InsertBefore($triggers,$principals) | Out-Null
                $actionArgs = $silXml.Task.SelectSingleNode("*[local-name()='Actions']/*[local-name()='Exec']/*[local-name()='Arguments']")
                if (-not $actionArgs) { throw 'Argumentos da tarefa Principal nao encontrados.' }
                $args = $actionArgs.InnerText -replace '(?i)(^|\s)-Silencioso(?=\s|$)',''
                if ($args -notmatch '(?i)(^|\s)-WindowStyle\s+Hidden(?=\s|$)') { $args = '-WindowStyle Hidden ' + $args }
                $actionArgs.InnerText = ($args.Trim() + ' -Silencioso')
                $settings = $silXml.Task.SelectSingleNode("*[local-name()='Settings']")
                $hidden = $settings.SelectSingleNode("*[local-name()='Hidden']")
                if ($hidden) { $hidden.InnerText = 'true' }
                else { $hidden = $silXml.CreateElement('Hidden',$ns); $hidden.InnerText = 'true'; $settings.AppendChild($hidden) | Out-Null }
                # O Silencioso nao exige ociosidade, mesmo quando a Principal exige.
                $idleOnly = $settings.SelectSingleNode("*[local-name()='RunOnlyIfIdle']")
                if ($idleOnly) { $idleOnly.InnerText = 'false' }
                else { $idleOnly = $silXml.CreateElement('RunOnlyIfIdle',$ns); $idleOnly.InnerText = 'false'; $settings.AppendChild($idleOnly) | Out-Null }
                # Executar mesmo em bateria; nao interromper quando alternar para bateria.
                foreach ($flag in @('DisallowStartIfOnBatteries','StopIfGoingOnBatteries')) {
                    $node = $settings.SelectSingleNode("*[local-name()='$flag']")
                    if ($node) { $node.InnerText = 'false' }
                    else { $node = $silXml.CreateElement($flag,$ns); $node.InnerText = 'false'; $settings.AppendChild($node) | Out-Null }
                }
                $nomeSilencioso = ($guardianPrincipal.TaskName -replace '^1\.', '2.') + ' - Execução Silenciosa'
                Register-ScheduledTask -TaskName $nomeSilencioso -TaskPath $taskFolder -Xml $silXml.OuterXml -Force -ErrorAction Stop | Out-Null
                foreach ($old in @('2. Guardian System','Guardian System','2. Guardian Silencioso','1. Guardian (Usuários Administradores) - Execução Silenciosa','1. Guardian (Usuários Restritos) - Execução Silenciosa','2. Guardian (Usuários Administradores) - Execução Silenciosa','2. Guardian (Usuários Restritos) - Execução Silenciosa')) {
                    if ($old -eq $nomeSilencioso) { continue }
                    if (Get-ScheduledTask -TaskName $old -TaskPath $taskFolder -ErrorAction SilentlyContinue) {
                        Unregister-ScheduledTask -TaskName $old -TaskPath $taskFolder -Confirm:$false -ErrorAction Stop
                    }
                }
                Write-Host "[Guardian Silencioso] '$nomeSilencioso' configurado: dias 11-20, 15:00, sem exigir ociosidade." -ForegroundColor Green
            } catch {
                Write-Warning "[Guardian Silencioso] Falha na configuracao: $($_.Exception.Message)"
            }
        } else {
            Write-Warning '[Guardian Silencioso] Tarefa Principal nao encontrada.'
        }


        # ----- TASK DO GUARDIAN GHOST (dias 21-25, 12:00, ociosidade 10min, aguardar 2h) -----
        $ghostTask = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                     Where-Object { $_.TaskName -in @("3. Guardian - Integridade do Sistema","3. Guardian Integridade do Sistema","3. Guardian Ghost") }

        # Migra o nome antigo sem alterar o agendamento do Ghost existente.
        foreach ($legacyName in @('3. Guardian Integridade do Sistema','3. Guardian Ghost')) {
            $legacyTask = Get-ScheduledTask -TaskName $legacyName -TaskPath $taskFolder -ErrorAction SilentlyContinue
            $newGhost = Get-ScheduledTask -TaskName '3. Guardian - Integridade do Sistema' -TaskPath $taskFolder -ErrorAction SilentlyContinue
            if ($legacyTask) {
                try {
                    if (-not $newGhost) {
                        $ghostXml = Export-ScheduledTask -TaskName $legacyName -TaskPath $taskFolder
                        Register-ScheduledTask -TaskName '3. Guardian - Integridade do Sistema' -TaskPath $taskFolder -Xml $ghostXml -Force -ErrorAction Stop | Out-Null
                    }
                    Unregister-ScheduledTask -TaskName $legacyName -TaskPath $taskFolder -Confirm:$false -ErrorAction Stop
                    $ghostTask = Get-ScheduledTask -TaskName '3. Guardian - Integridade do Sistema' -TaskPath $taskFolder
                } catch { Write-Warning "Falha ao renomear tarefa de integridade: $($_.Exception.Message)" }
            }
        }


        $ghostTask = Get-ScheduledTask -TaskName "3. Guardian - Integridade do Sistema" -TaskPath $taskFolder -ErrorAction SilentlyContinue
        $ghostPrecisaAjustar = $false

        if (-not $ghostTask) {
            $ghostPrecisaAjustar = $true
        }
        else {
            $trigger = $ghostTask.Triggers | Select-Object -First 1
            if ($trigger -and $trigger.CimClass.CimClassName -eq 'MSFT_TaskMonthlyTrigger') {
                $diasAtuais = @($trigger.DaysOfMonth) | Sort-Object
                $diasEsperados = @(21,22,23,24,25)
                if ($null -ne (Compare-Object $diasAtuais $diasEsperados -SyncWindow 0)) {
                    $ghostPrecisaAjustar = $true
                }
            }
            else {
                $ghostPrecisaAjustar = $true
            }
        }

        if ($ghostPrecisaAjustar) {
            $pwshPath7 = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
            if (-not $pwshPath7) { $pwshPath7 = "powershell.exe" }

            $action = New-ScheduledTaskAction `
                -Execute $pwshPath7 `
                -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Guardian\Guardian-Ghost.ps1"'
            $triggerGhost = New-ScheduledTaskTrigger -Daily -At "12:00"
            $principalGhost = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
            $settingsGhost = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
                -Hidden

            Register-ScheduledTask `
                -TaskName "3. Guardian - Integridade do Sistema" `
                -TaskPath $taskFolder `
                -Action $action `
                -Trigger $triggerGhost `
                -Settings $settingsGhost `
                -Principal $principalGhost `
                -Description "Guardian Ghost - System Integrity (Fase 2) silenciosa. Roda 1x/mes entre dias 21-25." `
                -Force | Out-Null

            $xml = [xml](Export-ScheduledTask -TaskName "3. Guardian - Integridade do Sistema" -TaskPath $taskFolder)
            try {
                if ($guardianPrincipal) {
                    $principalXmlCompat = [xml](Export-ScheduledTask -TaskName $guardianPrincipal.TaskName -TaskPath $taskFolder)
                    if ($principalXmlCompat.Task.version) { $xml.Task.version = $principalXmlCompat.Task.version }
                }
            } catch {}
            $ns = $xml.Task.NamespaceURI

            $oldTriggers = $xml.Task.SelectSingleNode("*[local-name()='Triggers']")
            if ($oldTriggers) { $xml.Task.RemoveChild($oldTriggers) | Out-Null }

            $newTriggers = $xml.CreateElement("Triggers", $ns)
            $calTrigger = $xml.CreateElement("CalendarTrigger", $ns)

            $startEl = $xml.CreateElement("StartBoundary", $ns)
            $startEl.InnerText = "2026-01-21T12:00:00"
            $calTrigger.AppendChild($startEl) | Out-Null

            $enabledEl = $xml.CreateElement("Enabled", $ns)
            $enabledEl.InnerText = "true"
            $calTrigger.AppendChild($enabledEl) | Out-Null

            $monthlyEl = $xml.CreateElement("ScheduleByMonth", $ns)

            $daysEl = $xml.CreateElement("DaysOfMonth", $ns)
            21..25 | ForEach-Object {
                $dayEl = $xml.CreateElement("Day", $ns)
                $dayEl.InnerText = $_
                $daysEl.AppendChild($dayEl) | Out-Null
            }
            $monthlyEl.AppendChild($daysEl) | Out-Null

            $monthsEl = $xml.CreateElement("Months", $ns)
            @("January","February","March","April","May","June","July","August","September","October","November","December") | ForEach-Object {
                $mEl = $xml.CreateElement($_, $ns)
                $monthsEl.AppendChild($mEl) | Out-Null
            }
            $monthlyEl.AppendChild($monthsEl) | Out-Null
            $calTrigger.AppendChild($monthlyEl) | Out-Null
            $newTriggers.AppendChild($calTrigger) | Out-Null

            $principals = $xml.Task.SelectSingleNode("*[local-name()='Principals']")
            $xml.Task.InsertBefore($newTriggers, $principals) | Out-Null

            $settingsNode = $xml.Task.SelectSingleNode("*[local-name()='Settings']")

            $roiNode = $settingsNode.SelectSingleNode("*[local-name()='RunOnlyIfIdle']")
            if ($roiNode) { $roiNode.InnerText = "true" }
            else {
                $roiEl = $xml.CreateElement("RunOnlyIfIdle", $ns); $roiEl.InnerText = "true"
                $settingsNode.AppendChild($roiEl) | Out-Null
            }

            $idleSettings = $settingsNode.SelectSingleNode("*[local-name()='IdleSettings']")
            if (-not $idleSettings) {
                $idleSettings = $xml.CreateElement("IdleSettings", $ns)
                $settingsNode.AppendChild($idleSettings) | Out-Null
            }
            foreach ($child in @($idleSettings.ChildNodes)) { $idleSettings.RemoveChild($child) | Out-Null }

            $durEl = $xml.CreateElement("Duration", $ns); $durEl.InnerText = "PT10M"
            $idleSettings.AppendChild($durEl) | Out-Null
            $waitEl = $xml.CreateElement("WaitTimeout", $ns); $waitEl.InnerText = "PT2H"
            $idleSettings.AppendChild($waitEl) | Out-Null
            $stopEl = $xml.CreateElement("StopOnIdleEnd", $ns); $stopEl.InnerText = "false"
            $idleSettings.AppendChild($stopEl) | Out-Null
            $restartEl = $xml.CreateElement("RestartOnIdle", $ns); $restartEl.InnerText = "false"
            $idleSettings.AppendChild($restartEl) | Out-Null

            Register-ScheduledTask -TaskName "3. Guardian - Integridade do Sistema" -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
            Unregister-ScheduledTask -TaskName "Guardian Ghost" -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "[Guardian Integridade do Sistema] Tarefa criada/corrigida: dias 21-25, 12:00." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[Tasks] Erro na padronização: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    # =========================================================================

    Show-Header "Atualização concluída com sucesso!" -Color Green
}

Update-GuardianFiles
