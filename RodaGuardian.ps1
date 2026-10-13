
# RodaGuardian.ps1
[CmdletBinding()]
param (
    # Caminho do PowerShell 7
    [string]$PwshPath = (Get-Command pwsh).Source,
    # Caminho do script principal Guardian
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',

    # Opções de janela
    [switch]$NoWindow,
    [switch]$Silencioso,
    [switch]$NonInteractive,
    [switch]$Maximized,

    # Parâmetros para Guardian.ps1
    [int[]]$ExecutaFases,
    [int[]]$PulaFases,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$LogLevel,
    [switch]$Simulado,
    [string]$FileServer,
    [string]$Cliente
)

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
            -TaskName "3. Guardian - Integridade do Sistema" `
            -TaskPath $taskFolder `
            -Action $action `
            -Trigger $triggerGhost `
            -Settings $settingsGhost `
            -Principal $principalGhost `
            -Description "Guardian Ghost - System Integrity (Fase 2) silenciosa. Roda 1x/mes entre dias 21-25." `
            -Force | Out-Null

        # Passo 2: Exportar e corrigir trigger + idle via XML
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


# -------------------------------
# Validações
# -------------------------------
if (-not (Test-Path -LiteralPath $PwshPath))   { Fail "PowerShell 7 não encontrado em: $PwshPath" }
if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail "Guardian.ps1 não encontrado em: $ScriptPath" }

# Desbloqueia o script alvo
try { Unblock-File -Path $ScriptPath -ErrorAction SilentlyContinue } catch {}

# Diretório de trabalho
$workDir = Split-Path -Path $ScriptPath -Parent

# -------------------------------
# Montagem segura dos argumentos
# -------------------------------
$argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File',$ScriptPath)
if ($NonInteractive) { $argList += '-NonInteractive' }
if ($ExecutaFases)   { $argList += '-ExecutaFases'; $argList += ($ExecutaFases -join ',') }
if ($PulaFases)      { $argList += '-PulaFases'; $argList += ($PulaFases -join ',') }
if ($LogLevel)       { $argList += '-LogLevel'; $argList += $LogLevel }
if ($Simulado)       { $argList += '-Simulado' }
if ($Silencioso)      { $argList += '-Silencioso' }
if ($FileServer)     { $argList += '-FileServer'; $argList += $FileServer }
if ($Cliente)        { $argList += '-Cliente'; $argList += "`"$Cliente`"" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow -or $Silencioso) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

# -------------------------------
# Log do comando final para debug
# -------------------------------
Show-Header "Comando final:" -Color Yellow
Write-Host "$PwshPath $($argList -join ' ')" -ForegroundColor Cyan

# -------------------------------
# Execução do Guardian
# -------------------------------
Push-Location $workDir
try {
    $argStringGuardian = ($argList | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f ($_ -replace '"','\"') } else { $_ }
    }) -join ' '

    # Marcador herdado pelo processo filho, independente da passagem de argumentos.
    if ($Silencioso) { $env:GUARDIAN_EXECUCAO_SILENCIOSA = '1' }
    $procGuardian = Start-Process `
        -FilePath $PwshPath `
        -ArgumentList $argStringGuardian `
        -WorkingDirectory $workDir `
        -WindowStyle $winStyle `
        -Wait `
        -PassThru

    if ($procGuardian.ExitCode -ne 0) { throw "Guardian retornou codigo $($procGuardian.ExitCode)" }
    Show-Header "Guardian executado com sucesso!" -Color Green
} catch {
    Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
}
Pop-Location
