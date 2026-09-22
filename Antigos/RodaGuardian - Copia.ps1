
# RodaGuardian.ps1
[CmdletBinding()]
param (
    # Caminho do PowerShell 7
    [string]$PwshPath = (Get-Command pwsh).Source,
    # Caminho do script principal Guardian
    [string]$ScriptPath = 'C:\Guardian\Guardian.ps1',

    # Opções de janela
    [switch]$NoWindow,
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
# VERIFICAÇÃO SILENCIOSA — Já rodou neste mês (dias 1-15)?
# Se sim, aborta imediatamente sem atualizar nada, sem mostrar nada.
# =========================================================================
$guardianJsonPath = "C:\Guardian\guardian.json"
if (Test-Path $guardianJsonPath) {
    try {
        $guardianData = Get-Content $guardianJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($guardianData.ultima_execucao) {
            $ultimaExecucao = [datetime]::Parse($guardianData.ultima_execucao)
            $agora = Get-Date

            # Mesma janela: mesmo mês, mesmo ano, e executou entre dias 1-15
            if ($ultimaExecucao.Year -eq $agora.Year -and
                $ultimaExecucao.Month -eq $agora.Month -and
                $ultimaExecucao.Day -ge 1 -and $ultimaExecucao.Day -le 15) {
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

    # ----- TASK DO GUARDIAN (dias 1-15, 12:00, ociosidade 10min, aguardar 2h) -----
    $guardianTasks = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                     Where-Object { $_.TaskName -like "*Guardian*" -and $_.TaskName -notlike "*Ghost*" }

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
        1..15 | ForEach-Object {
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
        $stopEl = $xml.CreateElement("StopOnIdleEnd", $ns); $stopEl.InnerText = "true"
        $idleSettings.AppendChild($stopEl) | Out-Null
        $restartEl = $xml.CreateElement("RestartOnIdle", $ns); $restartEl.InnerText = "false"
        $idleSettings.AppendChild($restartEl) | Out-Null

        Register-ScheduledTask -TaskName $task.TaskName -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
        Write-Host "[Guardian] Task '$($task.TaskName)' padronizada: dias 1-15, 12:00." -ForegroundColor Green
    }

    # ----- TASK DO GUARDIAN GHOST (dias 20-25, 12:00, ociosidade 10min, aguardar 2h) -----
    $ghostTask = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                 Where-Object { $_.TaskName -eq "Guardian Ghost" }

    $ghostPrecisaAjustar = $false

    if (-not $ghostTask) {
        $ghostPrecisaAjustar = $true
    }
    else {
        $trigger = $ghostTask.Triggers | Select-Object -First 1
        if ($trigger -and $trigger.CimClass.CimClassName -eq 'MSFT_TaskMonthlyTrigger') {
            $diasAtuais = @($trigger.DaysOfMonth) | Sort-Object
            $diasEsperados = @(20,21,22,23,24,25)
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
            -TaskName "Guardian Ghost" `
            -TaskPath $taskFolder `
            -Action $action `
            -Trigger $triggerGhost `
            -Settings $settingsGhost `
            -Principal $principalGhost `
            -Description "Guardian Ghost - System Integrity (Fase 2) silenciosa. Roda 1x/mes entre dias 20-25." `
            -Force | Out-Null

        # Passo 2: Exportar e corrigir trigger + idle via XML
        $xml = [xml](Export-ScheduledTask -TaskName "Guardian Ghost" -TaskPath $taskFolder)
        $ns = $xml.Task.NamespaceURI

        $oldTriggers = $xml.Task.SelectSingleNode("*[local-name()='Triggers']")
        if ($oldTriggers) { $xml.Task.RemoveChild($oldTriggers) | Out-Null }

        $newTriggers = $xml.CreateElement("Triggers", $ns)
        $calTrigger = $xml.CreateElement("CalendarTrigger", $ns)

        $startEl = $xml.CreateElement("StartBoundary", $ns)
        $startEl.InnerText = "2026-01-20T12:00:00"
        $calTrigger.AppendChild($startEl) | Out-Null

        $enabledEl = $xml.CreateElement("Enabled", $ns)
        $enabledEl.InnerText = "true"
        $calTrigger.AppendChild($enabledEl) | Out-Null

        $monthlyEl = $xml.CreateElement("ScheduleByMonth", $ns)

        $daysEl = $xml.CreateElement("DaysOfMonth", $ns)
        20..25 | ForEach-Object {
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
        $stopEl = $xml.CreateElement("StopOnIdleEnd", $ns); $stopEl.InnerText = "true"
        $idleSettings.AppendChild($stopEl) | Out-Null
        $restartEl = $xml.CreateElement("RestartOnIdle", $ns); $restartEl.InnerText = "false"
        $idleSettings.AppendChild($restartEl) | Out-Null

        Register-ScheduledTask -TaskName "Guardian Ghost" -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
        Write-Host "[Guardian Ghost] Task criada/corrigida: dias 20-25, 12:00." -ForegroundColor Green
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
if ($FileServer)     { $argList += '-FileServer'; $argList += $FileServer }
if ($Cliente)        { $argList += '-Cliente'; $argList += "`"$Cliente`"" }

# -------------------------------
# Configuração da janela
# -------------------------------
$winStyle = if ($NoWindow) { 'Hidden' } elseif ($Maximized) { 'Maximized' } else { 'Normal' }

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
    & $PwshPath @argList
    Show-Header "Guardian executado com sucesso!" -Color Green
} catch {
    Fail "Falha ao iniciar o Guardian.ps1: $($_.Exception.Message)"
}
Pop-Location
