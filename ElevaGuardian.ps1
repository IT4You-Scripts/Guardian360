# ElevaGuardian.ps1
# Executa Guardian.ps1 em PowerShell 7 usando credenciais criptografadas (AES)
# Responsável por elevação, contexto de execução e repasse seguro de parâmetros

[CmdletBinding()]
param (
    # Infraestrutura
    [string]$PwshPath = (Get-Command pwsh).Source,
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',
    [string]$CredPath   = 'C:\Guardian\credenciais.xml',
    [string]$KeyPath    = 'C:\Guardian\chave.key',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Guardian.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,
    [ValidateSet('INFO','WARN','ERROR','DEBUG')] [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

# -------------------------------
# Funções auxiliares
# -------------------------------
function Show-Header {
    param([string]$Text,[ConsoleColor]$Color='Cyan')
    $bar = '─' * ($Text.Length + 2)
    Write-Host ""
    Write-Host ("┌$bar┐") -ForegroundColor $Color
    Write-Host ("│ $Text │") -ForegroundColor $Color
    Write-Host ("└$bar┘") -ForegroundColor $Color
    Write-Host ""
}

function Fail {
    param([string]$Message)
    Show-Header $Message -Color Red
    Write-Host "O script será encerrado em 5 segundos..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    exit 1
}



# ----- TASK 0: PowerShell Update (XML fornecido, com limite de 2 horas) -----
function Sync-GuardianPowerShellTask {
    $taskPath = '\Guardian\'
    $taskName = '0. Guardian (PowerShell Update)'
    $desiredXml = @'
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>MORETTI-PC06\Administrador</Author>
    <Description>Atualiza PowerShell 7 por MSI oficial da Microsoft; sem Winget.</Description>
    <URI>\Guardian\0. Guardian (PowerShell Update)</URI>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T12:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByWeek>
        <DaysOfWeek>
          <Friday />
        </DaysOfWeek>
        <WeeksInterval>1</WeeksInterval>
      </ScheduleByWeek>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
      <Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Guardian\Functions\Update-PowerShellMSI.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
'@
    try {
        [xml]$expected = $desiredXml
        $existing = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        $needsUpdate = $true
        if ($existing) {
            [xml]$current = Export-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
            # Compara as folhas do XML de referencia (incluindo horario, SYSTEM,
            # bateria, argumentos, visibilidade e limite de execucao).
            function Test-GuardianTaskXmlNode {
                param([System.Xml.XmlNode]$Actual, [System.Xml.XmlNode]$Reference)
                if (-not $Actual -or $Actual.LocalName -ne $Reference.LocalName) { return $false }
                $referenceChildren = @($Reference.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
                if ($referenceChildren.Count -eq 0) { return ($Actual.InnerText -eq $Reference.InnerText) }
                $actualChildren = @($Actual.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
                foreach ($referenceChild in $referenceChildren) {
                    $sameNameReference = @($referenceChildren | Where-Object LocalName -eq $referenceChild.LocalName)
                    $index = [array]::IndexOf($sameNameReference, $referenceChild)
                    $sameNameActual = @($actualChildren | Where-Object LocalName -eq $referenceChild.LocalName)
                    if ($index -ge $sameNameActual.Count) { return $false }
                    if (-not (Test-GuardianTaskXmlNode -Actual $sameNameActual[$index] -Reference $referenceChild)) { return $false }
                }
                return $true
            }
            $matched = $true
            foreach ($section in @('Triggers','Principals','Settings','Actions')) {
                $expectedSection = $expected.Task.SelectSingleNode("*[local-name()='$section']")
                $currentSection = $current.Task.SelectSingleNode("*[local-name()='$section']")
                if (-not (Test-GuardianTaskXmlNode -Actual $currentSection -Reference $expectedSection)) {
                    $matched = $false
                    break
                }
            }
            if ($matched) {
                $expectedTriggerCount = @($expected.Task.Triggers.ChildNodes | Where-Object NodeType -eq Element).Count
                $actualTriggerCount = @($current.Task.Triggers.ChildNodes | Where-Object NodeType -eq Element).Count
                $expectedActionCount = @($expected.Task.Actions.ChildNodes | Where-Object NodeType -eq Element).Count
                $actualActionCount = @($current.Task.Actions.ChildNodes | Where-Object NodeType -eq Element).Count
                $matched = ($expectedTriggerCount -eq $actualTriggerCount -and $expectedActionCount -eq $actualActionCount)
            }
            $needsUpdate = -not $matched
        }
        if ($needsUpdate) {
            Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Xml $desiredXml -Force -ErrorAction Stop | Out-Null
            Write-Host '[Task 0] Criada/corrigida: sexta-feira 12:00, SYSTEM, limite de 2 horas.' -ForegroundColor Green
        }
        else {
            Write-Host '[Task 0] Configuracao validada; nenhuma alteracao necessaria.' -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[Task 0] Erro na criacao/validacao: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
# ----- FIM TASK 0 -----

Sync-GuardianPowerShellTask

# =========================================================================
# PADRONIZAÇÃO DAS TAREFAS NO AGENDADOR (via XML — testado e aprovado)
# =========================================================================
try {
    $taskFolder = "\Guardian\"

    # ----- TASK DO GUARDIAN (dias 1-10, 12:00, ociosidade 10min, aguardar 2h) -----
    $guardianTasks = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                     Where-Object {
                         $_.TaskName -like "*Guardian*" -and
                         $_.TaskName -notlike "*Ghost*" -and
                         $_.TaskName -notlike "*System*" -and
                          $_.TaskName -ne "0. Guardian (PowerShell Update)" -and
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

        # A tarefa principal também deve aparecer com a opção "Oculto" habilitada.
        $hiddenNode = $settingsNode.SelectSingleNode("*[local-name()='Hidden']")
        if ($hiddenNode) { $hiddenNode.InnerText = "true" }
        else {
            $hiddenEl = $xml.CreateElement("Hidden", $ns)
            $hiddenEl.InnerText = "true"
            $settingsNode.AppendChild($hiddenEl) | Out-Null
        }

        # Permitir iniciar também quando o computador estiver usando bateria.
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


    # ----- TASK GUARDIAN SYSTEM (dias 11-20, 15:00, SYSTEM, sem ociosidade) -----
    # Usa a acao da task principal como modelo e preserva seus argumentos.
    $guardianPrincipal = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                         Where-Object {
                             $_.TaskName -like "1. *Guardian*" -and
                             $_.TaskName -notlike "*Ghost*" -and
                             $_.TaskName -notlike "*System*"
                         } |
                         Select-Object -First 1

    if ($guardianPrincipal) {
        try {
            $acaoPrincipal = $guardianPrincipal.Actions | Select-Object -First 1
            $executeSystem = $acaoPrincipal.Execute
            $argumentsSystem = $acaoPrincipal.Arguments
            $workingDirSystem = $acaoPrincipal.WorkingDirectory

            # Sob SYSTEM nao ha necessidade de ElevaGuardian.
            $executeSystem = $executeSystem -replace '(?i)ElevaGuardian\.ps1','RodaGuardian.ps1'
            $argumentsSystem = $argumentsSystem -replace '(?i)ElevaGuardian\.ps1','RodaGuardian.ps1'

            $actionSystemParams = @{
                Execute  = $executeSystem
                Argument = $argumentsSystem
            }
            if (-not [string]::IsNullOrWhiteSpace($workingDirSystem)) {
                $actionSystemParams.WorkingDirectory = $workingDirSystem
            }
            $actionSystem = New-ScheduledTaskAction @actionSystemParams

            # Cria uma task base valida e depois troca somente o trigger mensal via XML,
            # usando o mesmo metodo ja empregado pelo Guardian Ghost.
            $triggerSystemBase = New-ScheduledTaskTrigger -Daily -At "15:00"
            $principalSystem = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settingsSystem = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
                -Hidden

            Register-ScheduledTask `
                -TaskName "2. Guardian System" `
                -TaskPath $taskFolder `
                -Action $actionSystem `
                -Trigger $triggerSystemBase `
                -Settings $settingsSystem `
                -Principal $principalSystem `
                -Description "Guardian System - fallback do Guardian principal. Dias 11-20 as 15:00." `
                -Force | Out-Null

            $systemXml = [xml](Export-ScheduledTask -TaskName "2. Guardian System" -TaskPath $taskFolder)
            try {
                $principalXmlCompat = [xml](Export-ScheduledTask -TaskName $guardianPrincipal.TaskName -TaskPath $taskFolder)
                if ($principalXmlCompat.Task.version) { $systemXml.Task.version = $principalXmlCompat.Task.version }
            } catch {}
            $ns = $systemXml.Task.NamespaceURI

            $oldTriggers = $systemXml.Task.SelectSingleNode("*[local-name()='Triggers']")
            if ($oldTriggers) { $systemXml.Task.RemoveChild($oldTriggers) | Out-Null }

            $newTriggers = $systemXml.CreateElement("Triggers", $ns)
            $calTrigger = $systemXml.CreateElement("CalendarTrigger", $ns)

            $startEl = $systemXml.CreateElement("StartBoundary", $ns)
            $startEl.InnerText = "2026-01-11T15:00:00"
            $calTrigger.AppendChild($startEl) | Out-Null

            $enabledEl = $systemXml.CreateElement("Enabled", $ns)
            $enabledEl.InnerText = "true"
            $calTrigger.AppendChild($enabledEl) | Out-Null

            $monthlyEl = $systemXml.CreateElement("ScheduleByMonth", $ns)
            $daysEl = $systemXml.CreateElement("DaysOfMonth", $ns)
            11..20 | ForEach-Object {
                $dayEl = $systemXml.CreateElement("Day", $ns)
                $dayEl.InnerText = $_
                $daysEl.AppendChild($dayEl) | Out-Null
            }
            $monthlyEl.AppendChild($daysEl) | Out-Null

            $monthsEl = $systemXml.CreateElement("Months", $ns)
            @("January","February","March","April","May","June","July","August","September","October","November","December") | ForEach-Object {
                $mEl = $systemXml.CreateElement($_, $ns)
                $monthsEl.AppendChild($mEl) | Out-Null
            }
            $monthlyEl.AppendChild($monthsEl) | Out-Null
            $calTrigger.AppendChild($monthlyEl) | Out-Null
            $newTriggers.AppendChild($calTrigger) | Out-Null

            $principals = $systemXml.Task.SelectSingleNode("*[local-name()='Principals']")
            $systemXml.Task.InsertBefore($newTriggers, $principals) | Out-Null

            Register-ScheduledTask -TaskName "2. Guardian System" -TaskPath $taskFolder -Xml ($systemXml.OuterXml) -Force | Out-Null
            Unregister-ScheduledTask -TaskName "Guardian System" -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "[Guardian System] Task criada/corrigida: dias 11-20, 15:00, SYSTEM, sem ociosidade." -ForegroundColor Green
        }
        catch {
            Write-Host "[Guardian System] Nao foi possivel criar/corrigir a task: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[Guardian System] Task principal nao encontrada; nenhuma configuracao foi inventada." -ForegroundColor Yellow
    }

    # ----- TASK DO GUARDIAN GHOST (dias 21-25, 12:00, ociosidade 10min, aguardar 2h) -----
    $ghostTask = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                 Where-Object { $_.TaskName -in @("3. Guardian Ghost","3. Guardian Ghost") }

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

        # Passo 1: Criar task base com cmdlets
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
            -TaskName "3. Guardian Ghost" `
            -TaskPath $taskFolder `
            -Action $action `
            -Trigger $triggerGhost `
            -Settings $settingsGhost `
            -Principal $principalGhost `
            -Description "Guardian Ghost - System Integrity (Fase 2) silenciosa. Roda 1x/mes entre dias 21-25." `
            -Force | Out-Null

        # Passo 2: Exportar e corrigir trigger + idle via XML
        $xml = [xml](Export-ScheduledTask -TaskName "3. Guardian Ghost" -TaskPath $taskFolder)
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

        Register-ScheduledTask -TaskName "3. Guardian Ghost" -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
        Unregister-ScheduledTask -TaskName "Guardian Ghost" -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[Guardian Ghost] Task criada/corrigida: dias 21-25, 12:00." -ForegroundColor Green
    }
}
catch {
    Write-Host "[Tasks] Erro na padronização: $($_.Exception.Message)" -ForegroundColor Yellow
}
# =========================================================================

# =========================================================================
# VERIFICAÇÃO SILENCIOSA — Já rodou neste mês?
# Se sim, aborta imediatamente sem atualizar nada, sem mostrar nada.
# =========================================================================
$guardianJsonPath = "C:\Guardian\guardian.json"
if (Test-Path $guardianJsonPath) {
    try {
        $guardianData = Get-Content $guardianJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($guardianData.ultima_execucao) {
            $ultimaExecucao = [datetime]::Parse($guardianData.ultima_execucao)
            $agora = Get-Date

            # Mesmo mês e mesmo ano: Guardian já executou, então encerra.
            if ($ultimaExecucao.Year -eq $agora.Year -and
                $ultimaExecucao.Month -eq $agora.Month) {
                exit 0
            }
        }
    }
    catch {}
}
# =========================================================================


# -------------------------------------------------------------------------------------------------------------------------
#region BootStrap - Atualiza somente o arquivo Update-GuardianFiles.ps1 — versão mínima e silenciosa
# -------------------------------------------------------------------------------------------------------------------------

$BaseUrl  = "https://raw.githubusercontent.com/IT4You-Scripts/Guardian360/main/Functions/Update-GuardianFiles.ps1"
$DestPath = "C:\Guardian\Functions\Update-GuardianFiles.ps1"
# Garante a pasta do atualizador mesmo em uma instalacao nova.
New-Item -ItemType Directory -Path (Split-Path -Parent $DestPath) -Force -ErrorAction Stop | Out-Null
$NoCache  = "?nocache=$(Get-Date -Format 'yyyyMMddHHmmss')"

# Remove o arquivo antigo
# Remove-Item -Path $DestPath -Force -ErrorAction SilentlyContinue

# Baixa o novo arquivo
Invoke-WebRequest -Uri ($BaseUrl + $NoCache) `
                  -OutFile $DestPath `
                  -UseBasicParsing `
                  -ErrorAction SilentlyContinue


# Atualização dos arquivos do Guardian 360 usando a função Update-GuardianFiles.ps1, que foi atualizada no cod acima
$updater = "C:\Guardian\Functions\Update-GuardianFiles.ps1"
if (Test-Path $updater) {
    . $updater
    Update-GuardianFiles
}

#endregion


# Validações iniciais (versão amigável)
# -------------------------------

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Fail "PowerShell 7 não foi localizado neste computador.`n`nInstale o PowerShell 7 antes de executar o Guardian."
}
$PwshPath = (Get-Command pwsh).Source

if (-not (Test-Path $ScriptPath)) {
    Fail "Arquivo principal do Guardian não foi encontrado. Caminho esperado:$ScriptPath"
}
$ScriptPath = (Resolve-Path $ScriptPath).Path

if (-not (Test-Path $CredPath)) {
    Fail "Arquivo de credenciais não encontrado. Local esperado:$CredPath"
}
$CredPath = (Resolve-Path $CredPath).Path

if (-not (Test-Path $KeyPath)) {
    Fail "Chave AES ausente.`n`nSem a chave não é possível descriptografar as credenciais. Local esperado:$KeyPath"
}
$KeyPath = (Resolve-Path $KeyPath).Path


# -------------------------------
# Leitura das credenciais AES
# -------------------------------
try {
    [xml]$xml = Get-Content -LiteralPath $CredPath -Raw
    $user = $xml.Credenciais.UserName
    $enc  = $xml.Credenciais.EncryptedPassword
} catch { Fail "Falha ao ler credenciais: $($_.Exception.Message)" }

if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($enc)) {
    Fail "Credenciais incompletas (UserName / EncryptedPassword)."
}

try {
    $keyBytes = [IO.File]::ReadAllBytes($KeyPath)
    $secure   = ConvertTo-SecureString -String $enc -Key $keyBytes
    if ($user -notlike '*\*' -and $user -notlike '*@*') { $user = "$env:COMPUTERNAME\$user" }
    $cred     = [System.Management.Automation.PSCredential]::new($user,$secure)
} catch { Fail "Não foi possível abrir as credenciais. Verifique chave AES." }

# =========================================================
# >>> PATCH JSON IPC (ARGUMENTOS ROBUSTOS)
# =========================================================

$argJsonPath = "C:\Guardian\guardian_arg.json"

$argsObj = @{
    FileServer    = $FileServer
    Cliente       = $Cliente
    ExecutaFases  = $ExecutaFases
    PulaFases     = $PulaFases
    LogLevel      = $LogLevel
    Simulado      = [bool]$Simulado
}

try {
    $argsObj | ConvertTo-Json -Depth 5 | Set-Content -Path $argJsonPath -Encoding UTF8
}
catch {
    Fail "Falha ao criar guardian_arg.json: $($_.Exception.Message)"
}

# =========================================================

# -------------------------------
# Montagem segura do comando
# -------------------------------
# NÃO repassar mais argumentos pela linha de comando
$argString = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""
if ($NonInteractive) { $argString += " -NonInteractive" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Log do comando final
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $argString" -ForegroundColor Cyan

# -------------------------------
# Execução do Guardian
# -------------------------------
try {
    $proc = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argString `
        -Credential $cred `
        -WorkingDirectory (Split-Path $ScriptPath -Parent) `
        -WindowStyle $winStyle `
        -UseNewEnvironment `
        -PassThru

    Show-Header "Guardian iniciado com sucesso. PID: $($proc.Id)" -Color Green
}
catch {
    Fail "Falha ao iniciar Guardian.ps1: $($_.Exception.Message)"
}
