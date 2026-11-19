#Requires -Version 7.0

<#
.SYNOPSIS
    Framework de Manutenção Preventiva, Atualização e Otimização para Windows 10 e 11.

.DESCRIPTION
    Este script orquestra um conjunto de funções organizadas em etapas cronológicas para:
	Executa funções específicas para cada fase:
		Fase 1	- Inventário de Hardware e Software
		Fase 2	- Integridade do sistema
		Fase 3	- Otimizações estruturais
		Fase 4	- Limpeza de arquivos temporários
		Fase 5	- Atualizações do Windows
        Fase 6	- Atualizações dos programas inatalados
        Fase 7	- Pós-atualização / Componentes
		Fase 8	- Otimização de Armazenamento
		Fase 9	- Segurança (Varredura contra malwares)
	Valida os arquivos de backup gerados pelo programa Macrium Reflect

.PARAMETER FileServer
    Hostname ou IP do servidor de arquivos (ex.: 192.168.0.2). Quando informado, a etapa "Send-LogToServer" é executada ao final,
    copiando o arquivo de log para \<FileServer>\TI\<ANO>\<MM. Mês>\COMPUTERNAME.log. Se não informado, a etapa é pulada.

.PARAMETER ExecutaFases
    Se informado, executa apenas as fases indicadas (IDs). Ex.: -ExecutaFases 1,3,5

.PARAMETER PulaFases
    Se informado, pula as fases indicadas (IDs). Ex.: -PulaFases 4,7

.PARAMETER LogLevel
    Nível de log: INFO, WARN, ERROR, DEBUG. Padrão: INFO.

.PARAMETER Simulado
    Modo ensaio: não executa ações destrutivas.

.NOTES
    Funcionalidades principais:
    - Validação do ambiente (Administrador, Windows, versão mínima do PowerShell)
    - Instalação automática do PowerShell 7+ se necessário (silenciosa; sem prompts)
    - Reexecução transparente no PowerShell 7+ se disponível
    - Tratamento de erros por etapa com registro em log (sem “erros vermelhos” na tela)
    - Execução autônoma (sem interação do usuário), ideal para Agendador de Tarefas
    - Compatível com o sistema operacional Microsoft Windows

.AUTHOR
    Tato, IT4You Ltda
.VERSION
    1.5
.LASTUPDATED
    15/02/2026
#>


[CmdletBinding()]
param(
  [int[]]$ExecutaFases,  # Se não for informado, executa todas as fases
  [int[]]$PulaFases,     # Se não for informado, nenhuma fase será pulada
  [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$LogLevel = 'INFO',
  [switch]$Simulado,
  [switch]$Dev,
  [switch]$EnviarApi,     # Modo ensaio: não executa ações destrutivas
  [string]$FileServer,   # Host/IP do servidor de arquivos para envio do log (opcional)
  [string]$Cliente       # Nome do nosso Cliente (preferencialmente, nome da Empresa onde ele trabalha)
)



$argJsonPath = "C:\Guardian\guardian_arg.json"
# Apenas JSON recente e legivel identifica uma chamada pelo ElevaGuardian.
$script:GuardianViaEleva = $false

if (Test-Path $argJsonPath) {
    $jsonArgs = Get-Content $argJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $jsonArgs -and
        (Get-Item -LiteralPath $argJsonPath).LastWriteTime -ge (Get-Date).AddMinutes(-10)) {
        $script:GuardianViaEleva = $true
    }

    if (-not $FileServer)   { $FileServer   = $jsonArgs.FileServer }
    if (-not $Cliente)      { $Cliente      = $jsonArgs.Cliente }
    if (-not $ExecutaFases) { $ExecutaFases = $jsonArgs.ExecutaFases }
    if (-not $PulaFases)    { $PulaFases    = $jsonArgs.PulaFases }
    if (-not $LogLevel)     { $LogLevel     = $jsonArgs.LogLevel }
    if (-not $Simulado)     { $Simulado     = $jsonArgs.Simulado }
    if (-not $Dev)          { $Dev          = [bool]$jsonArgs.Dev }
    if (-not $EnviarApi)    { $EnviarApi    = [bool]$jsonArgs.EnviarApi }
}


# -Debug e um parametro comum do PowerShell (CmdletBinding). Nao duplica-lo no param.
$script:GuardianDebugMode = ($PSBoundParameters.ContainsKey('Debug') -or ($null -ne (Get-Variable -Name jsonArgs -ErrorAction SilentlyContinue) -and [bool]$jsonArgs.DebugMode))
# -Debug controla a visibilidade do console; nao habilita tracing de cmdlets nativos.
# Evita mensagens DEPURAR: NetIPAddress ... emitidas por modulos do Windows.
$DebugPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Cliente)) {
    $Cliente = 'Cliente não identificado'
}

# ============================================================================================================================================================
# BLOQUEIO POR CLIENTE (OFFBOARDING) — SILENCIOSO
# A verificacao usa apenas copia local de $Cliente. Nao altera parametros nem clientes ativos.
# ============================================================================================================================================================
$DisabledClients = @(
    'Soneca Company',
    'Talude Comercial e Construtora Ltda'
)

function Normalize-ClienteName {
    param([string]$Nome)
    if ([string]::IsNullOrWhiteSpace($Nome)) { return '' }
    $n = ($Nome -replace '[\u00A0\u200B\u2007\u202F]', ' ') -replace '\s+', ' '
    $n = $n.Trim()
    # Remove somente aspas nas extremidades, inclusive repetidas e intercaladas.
    while ($n.Length -gt 0) {
        $novo = $n.Trim().Trim([char[]]@([char]34, [char]39)).Trim()
        if ($novo -ceq $n) { break }
        $n = $novo
    }
    return $n
}

# Sanitiza as aspas introduzidas pelo RodaGuardian/Agendador sem alterar os argumentos dos lancadores.
$Cliente = Normalize-ClienteName -Nome $Cliente
$clienteNorm = $Cliente
$blocked = $false
if ($clienteNorm.Length -gt 0) {
    foreach ($dc in $DisabledClients) {
        if ([string]::Equals($clienteNorm, (Normalize-ClienteName -Nome $dc), [System.StringComparison]::OrdinalIgnoreCase)) {
            $blocked = $true
            break
        }
    }
}

if ($blocked) {
    # Segurança v2.0: não remover tarefas automaticamente durante o offboarding.
    # Clientes desativados continuam bloqueados para execução. Remoções exigem
    # procedimento administrativo específico e separado do Guardian.
    exit 0
}


# ============================================================================================================================================================


# --- BLOCO DE ELEVAÇÃO E DETECÇÃO DO POWERSHELL 7 ---
# Se não estiver como Admin, reinicia com privilégios elevados
# No -Dev, nunca relançar sem repassar o switch: exige terminal já elevado.
if ($Dev -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '  ERRO  Execute o PowerShell 7 como Administrador para usar -Dev.' -ForegroundColor Red
    exit 1
}
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $scriptPath = $PSCommandPath
        $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
        if ($pwshPath) {
            Start-Process $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        } else {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        }
        exit
    } catch {
        Write-Host "Falha ao tentar elevar privilégios: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Se já está como Admin, mas não no PowerShell 7, reinicia nele (sem prompt)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if ($Dev) {
        Write-Host '  ERRO  O modo -Dev exige PowerShell 7; execucao interrompida.' -ForegroundColor Red
        exit 1
    }
    try {
        $scriptPath = $PSCommandPath
        $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
        if ($pwshPath) {
            Write-Host "Migrando para PowerShell 7..." -ForegroundColor Yellow
            Start-Process $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden
            exit
        } else {
            Write-Host "PowerShell 7 não encontrado. Continuando na versão atual." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Falha ao tentar reiniciar no PowerShell 7: $($_.Exception.Message)" -ForegroundColor Red
    }
}
# --- FIM DO BLOCO ---

# =========================================================================
# GERENCIAMENTO CENTRAL DAS QUATRO TAREFAS AGENDADAS
# Executado exclusivamente pelo Guardian.ps1, apos elevacao administrativa.
# Nao depende de RodaGuardian, ElevaGuardian, Atualiza ou Prepara.
# =========================================================================
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

    # ----- TASK DO GUARDIAN GHOST (dias 21-25, 12:00, SYSTEM, sem ociosidade) -----
    $ghostTask = Get-ScheduledTask -TaskPath $taskFolder -ErrorAction SilentlyContinue |
                 Where-Object { $_.TaskName -in @("3. Guardian Ghost","3. Guardian Ghost") }

    $ghostPrecisaAjustar = $false

    if (-not $ghostTask) {
        $ghostPrecisaAjustar = $true
    }
    else {
        # Corrige tambem tarefas existentes que ficaram exigindo ociosidade.
        if ($ghostTask.Settings.RunOnlyIfIdle) { $ghostPrecisaAjustar = $true }
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

        # Passo 2: Exportar e corrigir o trigger mensal via XML
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

        # Ghost executa como SYSTEM e nao depende de ociosidade.
        $roiNode = $settingsNode.SelectSingleNode("*[local-name()='RunOnlyIfIdle']")
        if ($roiNode) { $roiNode.InnerText = "false" }
        else {
            $roiEl = $xml.CreateElement("RunOnlyIfIdle", $ns); $roiEl.InnerText = "false"
            $settingsNode.AppendChild($roiEl) | Out-Null
        }

        # Remove apenas os parametros de ociosidade que nao se aplicam ao Ghost.
        $idleSettings = $settingsNode.SelectSingleNode("*[local-name()='IdleSettings']")
        if ($idleSettings) { $settingsNode.RemoveChild($idleSettings) | Out-Null }

        Register-ScheduledTask -TaskName "3. Guardian Ghost" -TaskPath $taskFolder -Xml ($xml.OuterXml) -Force | Out-Null
        Unregister-ScheduledTask -TaskName "Guardian Ghost" -TaskPath $taskFolder -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[Guardian Ghost] Task criada/corrigida: dias 21-25, 12:00, SYSTEM, sem ociosidade." -ForegroundColor Green
    }
}
catch {
    Write-Host "[Tasks] Erro na padronização: $($_.Exception.Message)" -ForegroundColor Yellow
}





#region Ajuste de parâmetros ExecutaFases e PulaFases


function Ajusta-Fases {
    param([object]$valor)

    if (-not $valor) { return @() }

    # Converte tudo para string
    $str = ($valor -join '') # Junta tudo como string

    # Se tiver vírgula, separa normalmente
    if ($str -match ',') {
        return ($str -split ',' | ForEach-Object { [int]([string]$_) })
    }

    # Se não tiver vírgula, separa cada dígito
    return ($str.ToCharArray() | ForEach-Object { [int]([string]$_) })
}


# Selecao efetiva: Fase 1 obrigatoria; Fase 2 exclusiva do Guardian Ghost.
$ExecutaFases = @(Ajusta-Fases $ExecutaFases | Where-Object { $_ -ge 1 -and $_ -le 9 -and $_ -ne 2 } | Sort-Object -Unique)
$PulaFases = @(Ajusta-Fases $PulaFases | Where-Object { $_ -ge 3 -and $_ -le 9 } | Sort-Object -Unique)
if ($ExecutaFases.Count -gt 0 -and $ExecutaFases -notcontains 1) {
    $ExecutaFases = @(1) + $ExecutaFases | Sort-Object -Unique
}

#endregion


# Preferências e ambiente
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Caminhos
$root    = Split-Path -Parent $PSCommandPath
$funcDir = Join-Path $root 'Functions'

# v2: nenhuma pasta ou arquivo LOG e criado. Resultados ficam na memoria.
$computer = $env:COMPUTERNAME.ToUpper()
$logFile = $null  # Compatibilidade temporaria; nunca sera escrito.






# === VERIFICAÇÃO DE EXECUÇÃO RECENTE — Movida para RodaGuardian.ps1 / ElevaGuardian.ps1 ===







# TLS forte (sem prompts)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# Resultados agregados
$global:Results = New-Object System.Collections.Generic.List[object]

# Lista global segura — garante que nunca será substituída por array fixo
if (-not $global:Results -or $global:Results.GetType().Name -ne 'List`1') {
    $global:Results = New-Object 'System.Collections.Generic.List[Object]'
}


# Log Conciso: controla escrita no arquivo
$global:ConciseLog = $true
$global:CurrentStepTitle = $null

#region Mapeamento das Etapas (nomes técnicos -> descrições amigáveis) ---
$StepDescriptions = @{
  'Get-SystemInventory'      = 'Coleta do Inventário de Hardware e Software'
  'Repair-SystemIntegrity'   = 'Verificação do Registro e dos arquivos do Windows'
  'Optimize-PowerSettings'   = 'Otimização das configurações de energia'
  'Optimize-NetworkSettings' = 'Otimização das configurações de rede (apenas DNS)'
  'Clear-BrowserCache'       = 'Limpeza do cache dos navegadores'
  'Clear-AllRecycleBins'     = 'Limpeza de todas as lixeiras'
  'Clear-TempFiles'          = 'Limpeza das pastas temporárias'
  'Clear-WindowsUpdateCache' = 'Limpeza do cache do Windows Update'
  'Clear-RecentFilesHistory' = 'Limpeza do histórico de arquivos recentes'
  'Update-WindowsOS'         = 'Atualização do Windows'
  'Update-MicrosoftStore'    = 'Atualização da Loja da Microsoft'
  'Block-AppUpdates'         = 'Bloqueia atualização do QGIS (Firewall)'
  'Update-WingetApps'        = 'Atualização dos programas instalados via Winget'
  'Remove-OldUpdateFiles'    = 'Limpeza dos arquivos temporários dos componentes do Windows'
  'Optimize-SSD'             = 'Otimização de todos os SSDs disponíveis'
  'Optimize-HDD'             = 'Desfragmentação de todos os discos físicos disponíveis'
  'Scan-AntiMalware'         = 'Varredura contra malwares com Windows Defender'
  'Confirm-MacriumBackup'    = 'Validação dos arquivos de backup do Macrium Reflect'
  'Send-LogToServer'         = 'Verificação e centralização do log no Servidor de Arquivos (opcional com -FileServer)'
  'Write-JsonResult'         = 'Atualiza arquivo Json' 
  'Optimize-JsonReport'      = 'Otimiza e trata arquivo Json' 
}
function Get-StepLabel {
  param([string]$Name)
  if ($StepDescriptions.ContainsKey($Name)) { return $StepDescriptions[$Name] }
  return $Name
}
#endregion

# Paleta (console amigável). Fallback se PSStyle não existir (ex.: PowerShell 5.x)
$pss = Get-Variable -Name PSStyle -ErrorAction SilentlyContinue
$hasStyle = ($null -ne $pss -and $null -ne $pss.Value)


if ($hasStyle) {
  $Cyan   = $pss.Value.Foreground.Cyan
  $Green  = $pss.Value.Foreground.Green
  $Yellow = $pss.Value.Foreground.Yellow
  $Gray   = $pss.Value.Foreground.BrightBlack
  $Red    = $pss.Value.Foreground.Red   # <-- Adicione esta linha
  $Reset  = $pss.Value.Reset
} else {
  $Cyan=''; $Green=''; $Yellow=''; $Gray=''; $Red=''; $Reset=''
}


# GUARDIAN 360 v2 - camada central de apresentacao (somente console).
# Eventos de INFO/DEBUG permanecem na memoria dos resultados das etapas, nao no terminal.
# Falhas e avisos relevantes continuam visiveis; nenhum arquivo de log e produzido.
function Write-GuardianStatus {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level='INFO')
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $msg = $Message.Trim() -replace '^\[(INFO|ALERTA|AVISO|ERRO|WARN|ERROR)\]\s*',''
    if ($msg -match '(?i)^N[aã]o existe a parti[cç][aã]o D\.?$') { return }
    if ($msg -match '(?i)^\[?INFO\]?\s*N[aã]o existe a parti[cç][aã]o D\.?$') { return }
    if ($Level -eq 'INFO' -or $Level -eq 'DEBUG') {
        # INFO tecnico nao e um evento a ser exibido na UI minimalista.
        return
    }
    $fg = if ($Level -eq 'ERROR') { 'Red' } else { 'Yellow' }
    $tag = if ($Level -eq 'ERROR') { 'ERRO' } else { 'AVISO' }
    Microsoft.PowerShell.Utility\Write-Host ('  {0,-10}{1}' -f $tag, $msg) -ForegroundColor $fg
}

# Futuro adaptador da interface WPF: uma mensagem operacional por evento.
function Write-GuardianConsoleEvent {
    param([string]$Text,[ValidateSet('OK','WARN','ERROR','NOTE')][string]$Kind='OK')
    $tag = switch ($Kind) { 'OK' {'OK'} 'WARN' {'AVISO'} 'ERROR' {'ERRO'} default {'INFO'} }
    $color = switch ($Kind) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'White'} }
    Microsoft.PowerShell.Utility\Write-Host ('  {0,-10}' -f $tag) -ForegroundColor $color -NoNewline
    Microsoft.PowerShell.Utility\Write-Host $Text -ForegroundColor White
}

function Show-Header {
    param([string]$Text,[string]$Color = $Cyan)
    Microsoft.PowerShell.Utility\Write-Host ''
    Microsoft.PowerShell.Utility\Write-Host '  GUARDIAN 360' -ForegroundColor White -NoNewline
    Microsoft.PowerShell.Utility\Write-Host '   v2.0' -ForegroundColor White -NoNewline
    if ($Dev) { Microsoft.PowerShell.Utility\Write-Host '   DEV' -ForegroundColor White }
    else { Microsoft.PowerShell.Utility\Write-Host '' }
    Microsoft.PowerShell.Utility\Write-Host ('  ' + ('─' * 51)) -ForegroundColor DarkGray
}
function Show-Phase {
    param([int]$Id,[string]$Title)
    Microsoft.PowerShell.Utility\Write-Host ''
    Microsoft.PowerShell.Utility\Write-Host ('  {0,-10}' -f ('{0:00}' -f $Id)) -ForegroundColor Cyan -NoNewline
    Microsoft.PowerShell.Utility\Write-Host $Title -ForegroundColor Cyan
}

function Show-StepStart { param([string]$Name) }
function Show-StepEnd {
    param([string]$Name,[TimeSpan]$Elapsed,[bool]$Ok)
    if ($Ok) { Write-GuardianConsoleEvent -Text $Name -Kind OK }
    else { Write-GuardianConsoleEvent -Text $Name -Kind ERROR }
}

function Test-IsAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

function Test-AdminOrExit {
  if (-not (Test-IsAdmin)) {
    Show-Header -Text 'Permissão insuficiente'
    Write-GuardianStatus "A execução requer privilégios administrativos. Agende como Admin/SYSTEM. Encerrando." 'ERROR'
    Pause
    exit 1
  }
}

function Initialize-Pwsh7 {
  if ($PSVersionTable.PSVersion.Major -ge 7) { return }
  Write-GuardianStatus 'PowerShell 7+ não detectado. Tentando instalação silenciosa...' 'INFO'
  $installed = $false
  try {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements --silent | Out-Null
      $installed = $true
    }
  } catch { Write-GuardianStatus ("Falha com winget: {0}" -f $_.Exception.Message) 'WARN' }

  if (-not $installed) {
    try {
      $msi = Join-Path $env:TEMP 'PowerShell7.msi'
      $url = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.1-win-x64.msi'
      Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
      Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
      $installed = $true
    } catch { Write-GuardianStatus ("Falha no download/instalação do MSI: {0}" -f $_.Exception.Message) 'WARN' }
  }

  if ($installed) {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if ($null -ne $pwsh) {
      Write-GuardianStatus 'Reiniciando no PowerShell 7 (silencioso)...' 'INFO'
      Start-Process $pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -WindowStyle Hidden
      exit 0
    }
  }

  Write-GuardianStatus 'PS7 não disponível. Continuando no host atual sem interromper.' 'WARN'
}

function Start-Logging {
  $dataHoraFormatada = Get-Date -Format "dd/MM/yyyy 'às' HH'h' mm'min'"
  Write-GuardianStatus    ("Guardian v1.5 ({0})" -f $dataHoraFormatada) 'INFO'
  Write-GuardianStatus "____________________________________________________________________________________________________________________________________"


}

function Stop-Logging { }

function Get-RebootPending {
    try {
        # CBS (Component-Based Servicing) pendente
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            return $true
        }

        # Windows Update pendente
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            return $true
        }

        # PendingFileRenameOperations real
        $val = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($val -and $val.Count -gt 0) { return $true }

        return $false
    } catch {
        return $false
    }
}


function Test-Internet { Test-Connection -ComputerName 1.1.1.1 -Quiet -Count 1 -ErrorAction SilentlyContinue }



function Get-PhysicalDisksByType {
    $list = @()
    try {
        # Tenta usar Get-PhysicalDisk (Windows 10/11 com Storage module)
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        if ($disks -and $disks.Count -gt 0) {
            $list = $disks | Select-Object FriendlyName, MediaType
        } else {
            # Fallback para ambientes sem Get-PhysicalDisk
            $fallback = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
            if ($fallback -and $fallback.Count -gt 0) {
                $list = $fallback | ForEach-Object {
                    [pscustomobject]@{
                        FriendlyName = $_.Model
                        MediaType    = (if ($_.Model -match 'SSD') { 'SSD' } else { 'HDD' })
                    }
                }
            }
        }
    } catch {
        $list = @() # Em caso de erro, retorna lista vazia
    }
    return @($list) # Força retorno como array
}



function Format-Elapsed {
  param([TimeSpan]$Elapsed)
  $min = [int][Math]::Floor($Elapsed.TotalMinutes)
  $sec = $Elapsed.Seconds
  return ('{0:00} min {1:00} seg' -f $min, $sec)
}

#region Bloco de Proteção QuickEdit
if (-not ('Kernel32' -as [type])) {
Add-Type @'
using System;
using System.Runtime.InteropServices;

public class Kernel32 {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
}
'@
}

function Invoke-QuickEditLog { param([string]$Message, [string]$Level = 'INFO') try { if (Get-Command Write-GuardianStatus -ErrorAction SilentlyContinue) { Write-GuardianStatus $Message $Level } } catch {} }

function Get-ConsoleInputMode {
    $handle = [Kernel32]::GetStdHandle(-10)
    $mode = 0
    [Kernel32]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    return $mode
}
function Set-ConsoleInputMode { param([uint32]$Mode) $handle = [Kernel32]::GetStdHandle(-10); [Kernel32]::SetConsoleMode($handle, $Mode) | Out-Null }

$ENABLE_QUICK_EDIT_MODE = 0x0040
$ENABLE_INSERT_MODE = 0x0020
$ENABLE_EXTENDED_FLAGS = 0x0080

function Enable-QuickEditProtection {
    $hostName = ''
    try { $hostName = $Host.Name } catch {}
    if ($hostName -match 'ISE|Visual Studio Code') { return }

    try {
        $currentMode = Get-ConsoleInputMode
        $newMode = $currentMode -band (-bnot $ENABLE_QUICK_EDIT_MODE)
        $newMode = $newMode -band (-bnot $ENABLE_INSERT_MODE)
        $newMode = $newMode -bor $ENABLE_EXTENDED_FLAGS
        Set-ConsoleInputMode $newMode
        Invoke-QuickEditLog 'Proteção Quick Edit habilitada.' 'DEBUG'
    } catch {
        Invoke-QuickEditLog ("Falha ao habilitar proteção Quick Edit: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Disable-QuickEditProtection {
    $hostName = ''
    try { $hostName = $Host.Name } catch {}
    if ($hostName -match 'ISE|Visual Studio Code') { return }

    try {
        $currentMode = Get-ConsoleInputMode
        $newMode = $currentMode -bor $ENABLE_QUICK_EDIT_MODE -bor $ENABLE_EXTENDED_FLAGS -bor $ENABLE_INSERT_MODE
        Set-ConsoleInputMode $newMode
        Invoke-QuickEditLog 'Proteção Quick Edit desabilitada.' 'DEBUG'
    } catch {
        Invoke-QuickEditLog ("Falha ao desabilitar proteção Quick Edit: {0}" -f $_.Exception.Message) 'WARN'
    }
}

# Patch: evitar múltiplas inscrições do mesmo handler de saída
if (-not (Get-Variable -Name QuickEdit_AtExitRegistered -Scope Script -ErrorAction SilentlyContinue)) {
  $script:QuickEdit_AtExitRegistered = $true
  try { Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Disable-QuickEditProtection } | Out-Null } catch {}
}
#endregion

#region Bloco de Aparência para o Console (Maximizar + Fundo Preto)
if (-not ('Win32.ConsoleWindow' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Win32 {
  public static class ConsoleWindow {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  }
}
'@
}

$script:_Console_OrigBgColor = $null

function Invoke-ConsoleLog { param([string]$Message,[string]$Level='DEBUG') try { if (Get-Command Write-GuardianStatus -ErrorAction SilentlyContinue) { Write-GuardianStatus $Message $Level } } catch {} }
function Test-HasRawUI { try { return ($null -ne $Host -and $null -ne $Host.UI -and $null -ne $Host.UI.RawUI) } catch { return $false } }

function Expand-ConsoleWindow {
  try {
    $hWnd = [Win32.ConsoleWindow]::GetConsoleWindow()
    if ($hWnd -ne [IntPtr]::Zero) { [void][Win32.ConsoleWindow]::ShowWindow($hWnd, 3) }
    if (Test-HasRawUI) {
      $raw = $Host.UI.RawUI
      $max = $raw.MaxWindowSize
      if ($max.Width -gt 0 -and $max.Height -gt 0) {
        $buf = $raw.BufferSize
        $newBuf = New-Object System.Management.Automation.Host.Size ([Math]::Max($buf.Width, $max.Width), [Math]::Max($buf.Height, [Math]::Max($max.Height, 300)))
        $raw.BufferSize = $newBuf
        $raw.WindowSize = New-Object System.Management.Automation.Host.Size ($max.Width, $max.Height)
      }
    }
    Invoke-ConsoleLog 'Console maximizado (API/RawUI).'
  } catch { Invoke-ConsoleLog ("Falha ao maximizar console: {0}" -f $_.Exception.Message) 'WARN' }
}

function Enable-ConsoleAppearance {
  [CmdletBinding()] param([switch]$ForceMaximize =$true)
  $hostName = '' ; try { $hostName = $Host.Name } catch {}
  $isDesignHost = ($hostName -match 'ISE' -or $hostName -match 'Visual Studio Code')

  if (Test-HasRawUI) {
    try {
      if ($null -eq $script:_Console_OrigBgColor) { $script:_Console_OrigBgColor = $Host.UI.RawUI.BackgroundColor }
      $Host.UI.RawUI.BackgroundColor = 'Black'
      Invoke-ConsoleLog 'Aparência: fundo preto aplicado.'
    } catch { Invoke-ConsoleLog ("Falha ao aplicar fundo preto: {0}" -f $_.Exception.Message) 'WARN' }
  }

  if (-not $isDesignHost) {
    if ($ForceMaximize) { Expand-ConsoleWindow }
  } else {
    Invoke-ConsoleLog "Maximização ignorada em host ($hostName)."
  }
}

function Disable-ConsoleAppearance {
  [CmdletBinding()] param()
  if (Test-HasRawUI) {
    try {
      if ($null -ne $script:_Console_OrigBgColor) {
        $Host.UI.RawUI.BackgroundColor = $script:_Console_OrigBgColor
        Invoke-ConsoleLog 'Aparência: fundo original restaurada.'
      }
    } catch { Invoke-ConsoleLog ("Falha ao restaurar aparência: {0}" -f $_.Exception.Message) 'WARN' }
    finally { $script:_Console_OrigBgColor = $null }
  }
}

if (-not (Get-Variable -Name ConsoleAppearance_AtExitHandler -Scope Script -ErrorAction SilentlyContinue)) {
  $script:ConsoleAppearance_AtExitHandler = { try { Disable-ConsoleAppearance } catch {} }
  try { Register-EngineEvent PowerShell.Exiting -Action $script:ConsoleAppearance_AtExitHandler | Out-Null } catch {}
}
#endregion



function Invoke-GuardianStep {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory=$false)][string]$Mensagem
    )

    $label = Get-StepLabel $Title
    $isWingetStep = ($Title -eq 'Update-WingetApps')
    if ($isWingetStep) {
        Microsoft.PowerShell.Utility\Write-Host ''
        Microsoft.PowerShell.Utility\Write-Host ('=' * 112) -ForegroundColor DarkGray
    }
    Write-GuardianStatus ("Iniciando: {0}" -f $Title) 'INFO'

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ok = $true
    $global:CurrentStepTitle = $Title
    $stepOutput = $null

    # Interceptor limitado a ESTA etapa. Silencia apenas a saida decorativa
    # das funcoes legadas. Nao altera o retorno tecnico nem captura stdout
    # de programas nativos, incluindo as barras azuis do winget.exe.
    function Write-Host {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Object,
              [object]$ForegroundColor,[object]$BackgroundColor,[switch]$NoNewline,
              [string]$Separator=' ')
    }
    # Oculta apenas o ProgressRecord amarelo do PowerShell; WinGet e nativo.
    $ProgressPreference = 'SilentlyContinue'

    try {
        if ($Simulado) {
            Write-GuardianStatus ("SIMULADO: ação não executada para '{0}'." -f $Title) 'DEBUG'
        }
        else {
            # 🔴 CAPTURA TUDO que a função produzir
            $stepOutput = & $Action 2>&1 | Out-String
        }
    }
    catch {
        $ok = $false
        Write-GuardianStatus ("Etapa '{0}' registrou erro: {1}" -f $Title, $_.ToString()) 'ERROR'
        $Mensagem = $_.ToString()
    }
    finally {
        $global:CurrentStepTitle = $null
    }

    $sw.Stop()

    # 🔴 Se não veio mensagem manual mas houve saída da função
    if (-not $Mensagem -and $stepOutput) {
        $Mensagem = $stepOutput.Trim()
    }

    # Proteção contra corrupção do global:Results
    if ($null -eq $global:Results -or $global:Results.GetType().Name -ne 'List`1') {
        $safeCopy = @($global:Results)
        $global:Results = New-Object 'System.Collections.Generic.List[Object]'
        foreach ($i in $safeCopy) { $global:Results.Add($i) }
    }

    # Registro da etapa
    $global:Results.Add([pscustomobject]@{
        Etapa        = $label
        EtapaTecnica = $Title
        Sucesso      = $ok
        Tempo        = $sw.Elapsed
        Mensagem     = $Mensagem
    })

    if ($isWingetStep) {
        Microsoft.PowerShell.Utility\Write-Host ('=' * 112) -ForegroundColor DarkGray
        Microsoft.PowerShell.Utility\Write-Host ''
    }
    Show-StepEnd -Name $label -Elapsed $sw.Elapsed -Ok:$ok
}





# =========================================================================
# Guardian 360 v2.0 - interface de acompanhamento independente (sem arquivo IPC)
# O motor permanece dono da manutencao, da telemetria e do JSON definitivo.
# A UI recebe SOMENTE informacoes de andamento, por TCP localhost.
# =========================================================================
$script:GuardianUiPort = 0
$script:GuardianUiProcess = $null
$script:GuardianUiAvailable = $false

function Initialize-GuardianLiveUI {
    try {
        # Windows SYSTEM (sessao 0) nao tem desktop interativo para apresentar WPF.
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($identity -match '(?i)(^|\\)SYSTEM$') { return }
        $uiScript = Join-Path $PSScriptRoot 'Functions\Show-GuardianLiveUI.ps1'
        if (-not (Test-Path -LiteralPath $uiScript)) {
            Microsoft.PowerShell.Utility\Write-Host '  AVISO  Interface WPF nao instalada; manutencao continua.' -ForegroundColor Yellow
            return
        }
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $script:GuardianUiPort = [int]$probe.LocalEndpoint.Port
        $probe.Stop()
        $pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source
        $uiArgs = '-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Port {1} -Cliente "{2}" -Computador "{3}" -EnginePid {4}' -f $uiScript, $script:GuardianUiPort, ($Cliente -replace '"',''), ($env:COMPUTERNAME -replace '"',''), $PID
        # Apenas o console hospedeiro do pwsh fica oculto. A janela WPF tem
        # ShowInTaskbar=True e e apresentada por ShowDialog(), separadamente.
        $script:GuardianUiProcess = Start-Process -FilePath $pwshExe -ArgumentList $uiArgs -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:GuardianUiAvailable = $true
        Start-Sleep -Milliseconds 750
    } catch {
        $script:GuardianUiAvailable = $false
        Microsoft.PowerShell.Utility\Write-Host ('  AVISO  Nao foi possivel iniciar a interface: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Send-GuardianLiveEvent {
    param([string]$Type, [string]$Label = '', [int]$Percent = 0, [string]$Status = '', [hashtable]$Data = @{})
    if (-not $script:GuardianUiAvailable -or $script:GuardianUiPort -le 0) { return }
    try {
        $payload = @{ type=$Type; label=$Label; percent=$Percent; status=$Status; data=$Data } | ConvertTo-Json -Compress -Depth 4
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connection = $client.BeginConnect([System.Net.IPAddress]::Loopback, $script:GuardianUiPort, $null, $null)
            if (-not $connection.AsyncWaitHandle.WaitOne(200)) { return }
            $client.EndConnect($connection)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $stream = $client.GetStream()
            $stream.WriteTimeout = 200
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Flush()
        } finally { $client.Dispose() }
    } catch { } # Uma UI fechada nunca pode interromper o motor.
}

# 1) Pré-requisitos para o Script poder rodar corretamente (sem prompts)
Test-AdminOrExit
Initialize-Pwsh7
Enable-QuickEditProtection
# Garantia adicional: nao reexibir o console em execucao normal.
# A classe Win32.ConsoleWindow ja foi definida no bloco de aparencia acima.
if (-not $script:GuardianDebugMode) {
    try {
        $guardianConsole = [Win32.ConsoleWindow]::GetConsoleWindow()
        if ($guardianConsole -ne [IntPtr]::Zero) {
            [void][Win32.ConsoleWindow]::ShowWindow($guardianConsole, 0)
        }
    } catch { }
}
Enable-ConsoleAppearance -ForceMaximize:$script:GuardianDebugMode
Clear-Host
Show-Header -Text 'Guardian 360 v2.0'
Initialize-GuardianLiveUI
Send-GuardianLiveEvent -Type 'start' -Label 'Preparando manutenção preventiva' -Percent 0

# v2 console: inicializa o estado antes do bloco protegido.
# Caso uma falha ocorra antes da montagem do relatorio, o finally permanece seguro.
$script:GuardianRelatorioEmMemoria = $null
$script:GuardianJsonDestino = $null
$script:GuardianFalhaGeral = $false
$script:GuardianTasksPadronizadas = $false
$jsonResults = @()
$global:GuardianEnvioApiStatus = 'Nao iniciado'

try {
  # 2) Carregar funções do repositório
  $functionFiles = @(
    'Get-SystemInventory.ps1',
    'Repair-SystemIntegrity.ps1',
    'Optimize-PowerSettings.ps1',
    'Optimize-NetworkSettings.ps1',
    'Clear-BrowserCache.ps1',
    'Clear-AllRecycleBins.ps1',
    'Clear-TempFiles.ps1',
    'Clear-WindowsUpdateCache.ps1',
    'Clear-RecentFilesHistory.ps1',
    'Block-AppUpdates.ps1',
    'Update-WindowsOS.ps1',
    'Update-MicrosoftStore.ps1',
    'Update-WingetApps.ps1',
    'Remove-OldUpdateFiles.ps1',
    'Optimize-SSD.ps1',
    'Optimize-HDD.ps1',
    'Scan-AntiMalware.ps1',
    'Confirm-MacriumBackup.ps1',
    'Send-LogToServer.ps1',
    'Write-JsonResult.ps1'
  )
  foreach ($ff in $functionFiles) {
    $path = Join-Path $funcDir $ff
    if (-not (Test-Path $path)) {
      Write-GuardianStatus ("Arquivo de função não encontrado: {0}" -f $path) 'ERROR'
      continue
    }
    try { . $path } catch { Write-GuardianStatus ("Falha ao carregar {0}: {1}" -f $ff, $_.ToString()) 'ERROR' }
  }

  # 3) Detectores de cenário
  $hasInet = Test-Internet

  
  # Garante que sempre teremos um array, mesmo se a função retornar $null
 
# Garante que sempre teremos um array, mesmo se a função retornar $null
$disks = @(Get-PhysicalDisksByType)

# Cria listas separadas para SSD e HDD
$ssdList = @($disks | Where-Object { $_.MediaType -match 'SSD' })
$hddList = @($disks | Where-Object { $_.MediaType -match 'HDD|Unspecified' })

# Flags seguras
$hasSSD = ($ssdList.Count -gt 0)
$hasHDD = ($hddList.Count -gt 0)





  # Coleta passiva do TeamViewer — sem instalar, executar ou alterar o aplicativo.
  # O resultado compoe o JSON local da vistoria quando a Fase 1 e executada.
  $script:TeamViewerInfo = $null
  function Get-GuardianTeamViewerInfo {
      $info = [ordered]@{
          Instalado = $false
          ID        = $null
          Versao    = $null
          Status    = 'NaoInstalado'
      }
      try {
          $keys = @(
              'HKLM:\SOFTWARE\TeamViewer',
              'HKLM:\SOFTWARE\WOW6432Node\TeamViewer',
              'HKCU:\SOFTWARE\TeamViewer'
          )
          $uninstallKeys = @(
              'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
          )
          $instalacoes = @(
              foreach ($key in $uninstallKeys) {
                  Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
                      Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match '^TeamViewer(?:\s|$)' }
              }
          )
          $servico = Get-Service -Name 'TeamViewer' -ErrorAction SilentlyContinue
          $arquivos = @(
              (Join-Path $env:ProgramFiles 'TeamViewer\TeamViewer.exe'),
              (Join-Path $env:ProgramFiles 'TeamViewer\TeamViewer_Service.exe')
          )
          if (${env:ProgramFiles(x86)}) {
              $arquivos += Join-Path ${env:ProgramFiles(x86)} 'TeamViewer\TeamViewer.exe'
              $arquivos += Join-Path ${env:ProgramFiles(x86)} 'TeamViewer\TeamViewer_Service.exe'
          }
          $info.Instalado = (($instalacoes.Count -gt 0) -or ($null -ne $servico) -or
                             (@($arquivos | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0))
          if (-not $info.Instalado) { return [pscustomobject]$info }

          $info.Status = 'IDIndisponivel'
          foreach ($instalacao in $instalacoes) {
              if (-not [string]::IsNullOrWhiteSpace([string]$instalacao.DisplayVersion)) {
                  $info.Versao = [string]$instalacao.DisplayVersion
                  break
              }
          }
          # O ClientID pode residir na chave principal ou em VersionN (ex.: Version13).
          # Apenas leitura: nunca abre o TeamViewer, nem altera o Registro.
          foreach ($key in $keys) {
              $candidateKeys = @($key)
              $candidateKeys += @(
                  Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue |
                      Where-Object { $_.PSChildName -match '^Version\d+$' } |
                      Sort-Object { if ($_.PSChildName -match '^Version(\d+)$') { [int]$Matches[1] } else { 0 } } -Descending |
                      ForEach-Object { $_.PSPath }
              )
              foreach ($candidateKey in $candidateKeys) {
                  $item = Get-ItemProperty -LiteralPath $candidateKey -ErrorAction SilentlyContinue
                  if ($null -eq $item) { continue }
                  if (-not $info.Versao -and $item.PSObject.Properties['Version']) {
                      $info.Versao = [string]$item.Version
                  }
                  $id = if ($item.PSObject.Properties['ClientID']) { ([string]$item.ClientID).Trim() } else { '' }
                  if ($id -match '^[0-9]+$' -and $id -ne '0') {
                      $info.ID = $id
                      $info.Status = 'OK'
                      break
                  }
              }
              if ($info.ID) { break }
          }

          # Fallback oficial para instalacoes sem ClientID no Registro.
          # Instala TeamViewerPS sob demanda apenas quando o TeamViewer esta presente
          # e nenhuma chave do Registro forneceu um ID. Sem prompt ou Write-Log.
          if (-not $info.ID) {
              try {
                  $teamViewerCmd = Get-Command -Name 'Get-TeamViewerId' -ErrorAction SilentlyContinue
                  if (-not $teamViewerCmd) {
                      try {
                          Import-Module -Name TeamViewerPS -ErrorAction Stop -WarningAction SilentlyContinue 6>$null | Out-Null
                      } catch { }
                      $teamViewerCmd = Get-Command -Name 'Get-TeamViewerId' -ErrorAction SilentlyContinue
                  }
                  if (-not $teamViewerCmd -and (Get-Command -Name 'Install-Module' -ErrorAction SilentlyContinue)) {
                      # AllUsers e compartilhado entre administradores, usuarios e SYSTEM.
                      # Sem elevacao, usa CurrentUser em vez de falhar por permissao.
                      $scope = 'CurrentUser'
                      try {
                          $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
                          if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                              $scope = 'AllUsers'
                          }
                      } catch { }

                      # Instalacao isolada e limitada a 60 s; nunca aguarda interacao.
                      $installJob = $null
                      try {
                          $installJob = Start-Job -ScriptBlock {
                              param([string]$InstallScope)
                              $ProgressPreference = 'SilentlyContinue'
                              $WarningPreference = 'SilentlyContinue'
                              $InformationPreference = 'SilentlyContinue'
                              $ConfirmPreference = 'None'
                              $ErrorActionPreference = 'Stop'
                              Install-Module -Name 'TeamViewerPS' -Scope $InstallScope -Repository 'PSGallery' -Force -AllowClobber -Confirm:$false -ErrorAction Stop *> $null
                          } -ArgumentList $scope -ErrorAction Stop
                          $finished = Wait-Job -Job $installJob -Timeout 60 -ErrorAction SilentlyContinue
                          if ($finished) {
                              Receive-Job -Job $installJob -ErrorAction Stop *> $null
                          } else {
                              Stop-Job -Job $installJob -ErrorAction SilentlyContinue
                          }
                      } catch {
                          # Galeria indisponivel: nao comprometer a vistoria.
                      } finally {
                          if ($installJob) {
                              Remove-Job -Job $installJob -Force -ErrorAction SilentlyContinue
                          }
                      }

                      try {
                          Import-Module -Name TeamViewerPS -ErrorAction Stop -WarningAction SilentlyContinue 6>$null | Out-Null
                      } catch { }
                      $teamViewerCmd = Get-Command -Name 'Get-TeamViewerId' -ErrorAction SilentlyContinue
                  }
                  if ($teamViewerCmd) {
                      $moduleId = Get-TeamViewerId -ErrorAction Stop 6>$null
                      $id = ([string]$moduleId).Trim()
                      if ($id -match '^[0-9]+$' -and $id -ne '0') {
                          $info.ID = $id
                          $info.Status = 'OK'
                      }
                  }
              } catch {
                  # Sem identificador: prosseguir com IDIndisponivel, sem interromper o Guardian.
              }
          }
      } catch {
          $info.Status = 'ErroLeitura'
      }
      return [pscustomobject]$info
  }

  # 4) Fases e passos
  $Phases = @(
    @{ Id=1; Title='Inventário de Hardware e Software'; Steps=@(
        @{ Name='Get-SystemInventory';   Action={ Get-SystemInventory } }
      )},
    @{ Id=3; Title='Otimizações Estruturais'; Steps=@(
        @{ Name='Optimize-PowerSettings';    Action={ Optimize-PowerSettings } },
        @{ Name='Optimize-NetworkSettings';  Action={ Optimize-NetworkSettings } }
      )},
    @{ Id=4; Title='Limpeza de arquivos temporários'; Steps=@(
        #@{ Name='Clear-BrowserCache';        Action={ Clear-BrowserCache } },
        @{ Name='Clear-WindowsUpdateCache';  Action={ Clear-WindowsUpdateCache } },
        @{ Name='Clear-TempFiles';           Action={ Clear-TempFiles } },
        @{ Name='Clear-AllRecycleBins';      Action={ Clear-AllRecycleBins } }
        #@{ Name='Clear-RecentFilesHistory';  Action={ Clear-RecentFilesHistory } }
      )},
    @{ Id=5; Title='Atualizações do Windows'; Steps=@(
        @{ Name='Update-WindowsOS'; Action={ if($hasInet){ Update-WindowsOS } else { Write-GuardianStatus 'Sem internet: pulando Update-WindowsOS' 'WARN' } } }
      )},
    @{ Id=6; Title='Atualizações dos programas instalados'; Steps=@(
        # @{ Name='Block-AppUpdates';  Action={ Block-AppUpdates } },
        @{ Name='Update-WingetApps';    Action={ if($hasInet){ Update-WingetApps -AtualizarUsuario:($script:GuardianViaEleva -or ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')) } else { Write-GuardianStatus 'Sem internet: pulando Update-WingetApps' 'WARN' } } }
      )},
    @{ Id=7; Title='Pós-atualização / Componentes'; Steps=@(
        @{ Name='Remove-OldUpdateFiles'; Action={ Remove-OldUpdateFiles } }
      )},
    @{ Id=8; Title='Otimização de Armazenamento'; Steps=@(
        @{ Name='Optimize-SSD'; Action={ if($hasSSD){ Optimize-SSD } else { Write-GuardianStatus 'Nenhum SSD detectado: pulando Optimize-SSD' 'INFO' } } },
        @{ Name='Optimize-HDD'; Action={ if($hasHDD){ Optimize-HDD } else { Write-GuardianStatus 'Nenhum HDD detectado: pulando Optimize-HDD' 'INFO' } } }
      )},
    @{ Id=9; Title='Segurança'; Steps=@(
        @{ Name='Scan-AntiMalware';       Action={ Scan-AntiMalware } }        
      )}
  )


  # Incício do Cronômetro do Script
  $scriptStart = [Diagnostics.Stopwatch]::StartNew()


  # Exibe a UI amigável enquanto o script continua rodand
  # Show-GuardianUI
  # v2 laboratorio: interface WPF desativada durante a validacao do motor.
  


# Adicione no início do script:
function DoEvents { }  # v2 console

# Plano efetivo: sem Fase 2 e com Fase 1 obrigatoria.
$script:GuardianSelectedPhases = @($Phases | Where-Object {
    (-not $ExecutaFases -or $ExecutaFases -contains $_.Id) -and
    (-not $PulaFases -or $PulaFases -notcontains $_.Id)
})
$script:GuardianPhaseCount = @($script:GuardianSelectedPhases).Count
$TotalSteps = 0
foreach ($plannedPhase in $script:GuardianSelectedPhases) {
    $TotalSteps += @($plannedPhase.Steps).Count
}
$CurrentPhaseOrdinal = 0

# Ajusta a barra de progresso para refletir isso
# v2 console: nao ha controle WPF nesta etapa.

# Contador de passos concluídos
$CurrentStep = 0


 Write-Host ""
 Write-Host ('  {0,-12} {1}' -f 'Cliente', $Cliente) -ForegroundColor White
Write-Host ('  {0,-12} {1}' -f 'Computador', $env:COMPUTERNAME) -ForegroundColor White




# Preflight PawnIO: antes da Fase 1 para aparecer no inventario de software.
# Reutiliza a instalacao do modulo de telemetria; falhas nao bloqueiam o Guardian.
if ((-not $ExecutaFases -or $ExecutaFases -contains 1) -and
    (-not $PulaFases -or $PulaFases -notcontains 1) -and -not $Simulado) {
    try {
        $scriptPawnIO = Join-Path $funcDir 'Get-HardwareTelemetry.ps1'
        if (Test-Path -LiteralPath $scriptPawnIO -PathType Leaf) {
            $preparoPawnIO = & $scriptPawnIO -PrepararPawnIO
            $estadoPawnIO = [string]$preparoPawnIO.Estado

            foreach ($avisoPawnIO in @($preparoPawnIO.Avisos)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$avisoPawnIO)) {
                    Write-GuardianStatus ("PawnIO: {0}" -f $avisoPawnIO) 'WARN'
                }
            }
        } else {
            Write-GuardianStatus 'PawnIO: modulo de telemetria ausente; inventario segue normalmente.' 'WARN'
        }
    } catch {
        Write-GuardianStatus ("PawnIO: preflight nao concluido: {0}. Inventario segue normalmente." -f $_.Exception.Message) 'WARN'
    }
}

# ===============================================================================
# Preflight NetTime: somente antes do inventario (Fase 1).
# Nao atualiza programas instalados; nao modifica W32Time ou politicas de dominio.
# Falhas sao isoladas e nunca impedem a vistoria.
# ===============================================================================
function Test-GuardianProgramInstalled {
    param([ValidateSet('NetTime','7-Zip')][string]$Programa)

    # Caminhos padrao: permitem detectar o executavel mesmo sem entrada Uninstall.
    $caminhos = if ($Programa -eq '7-Zip') {
        @(
            (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' })
        )
    } else {
        @(
            (Join-Path $env:ProgramFiles 'NetTime\NetTimeService.exe'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'NetTime\NetTimeService.exe' })
        )
    }
    foreach ($caminho in $caminhos) {
        if ($caminho -and (Test-Path -LiteralPath $caminho -PathType Leaf)) { return $true }
    }

    foreach ($raiz in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        foreach ($entrada in @(Get-ItemProperty -Path $raiz -ErrorAction SilentlyContinue)) {
            $nome = if ($entrada.PSObject.Properties['DisplayName']) { [string]$entrada.DisplayName } else { '' }
            if ($Programa -eq 'NetTime' -and $nome -match '^NetTime(?:\s|$)') { return $true }
            if ($Programa -eq '7-Zip'   -and $nome -match '^7-Zip(?:\s|$)') { return $true }
        }
    }
    return $false
}

function Install-GuardianOptionalProgram {
    param([ValidateSet('NetTime','7-Zip')][string]$Programa)

    if (Test-GuardianProgramInstalled -Programa $Programa) {
        Write-GuardianStatus ("{0}: ja instalado; nenhuma acao necessaria." -f $Programa) 'INFO'
        return
    }

    # Instaladores oficiais de versoes estaveis (sem atualizacao automatica).
    # 7-Zip 26.05 x64: site oficial -> repositorio oficial ip7z.
    # NetTime 3.14: versao estavel, nao a versao alpha 3.20.
    if ($Programa -eq '7-Zip') {
        $url = 'https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe'
        $argumentos = '/S'
        if (-not [Environment]::Is64BitOperatingSystem -or
            [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
            Write-GuardianStatus '7-Zip: instalador configurado apenas para Windows x64; instalacao ignorada neste equipamento.' 'WARN'
            return
        }
    } else {
        $url = 'https://www.timesynctool.com/NetTimeSetup-314.exe'
        $argumentos = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
    }

    $diretorio = Join-Path ([IO.Path]::GetTempPath()) ('Guardian_OptionalApps_' + [guid]::NewGuid().ToString('N'))
    $instalador = Join-Path $diretorio ($Programa.Replace('-','') + '.exe')
    try {
        New-Item -ItemType Directory -Path $diretorio -Force -ErrorAction Stop | Out-Null
        Write-GuardianStatus ("{0}: ausente; baixando instalador oficial." -f $Programa) 'INFO'
        Invoke-WebRequest -Uri $url -OutFile $instalador -MaximumRedirection 5 -TimeoutSec 90 -ErrorAction Stop
        $arquivo = Get-Item -LiteralPath $instalador -ErrorAction Stop
        if ($arquivo.Length -lt 50000) { throw 'Arquivo baixado invalido ou incompleto.' }
        # Nao executar binario com assinatura explicitamente invalida.
        $assinatura = Get-AuthenticodeSignature -LiteralPath $instalador -ErrorAction Stop
        if ($assinatura.Status -notin @('Valid','NotSigned')) {
            throw ("Assinatura do instalador nao confiavel: {0}" -f $assinatura.Status)
        }

        $processo = Start-Process -FilePath $instalador -ArgumentList $argumentos -PassThru -WindowStyle Hidden -ErrorAction Stop
        if (-not $processo.WaitForExit(180000)) {
            try { $processo.Kill() } catch { }
            throw 'Instalador ultrapassou o limite de 180 segundos.'
        }
        if ($processo.ExitCode -notin @(0,3010)) {
            throw ("Instalador retornou codigo {0}" -f $processo.ExitCode)
        }

        # O instalador pode registrar o produto alguns segundos apos sair.
        $confirmado = $false
        for ($tentativa=0; $tentativa -lt 10; $tentativa++) {
            if (Test-GuardianProgramInstalled -Programa $Programa) { $confirmado = $true; break }
            Start-Sleep -Seconds 2
        }
        if ($confirmado) {
            Write-GuardianStatus ("{0}: instalado silenciosamente antes do inventario." -f $Programa) 'INFO'
            if ($Programa -eq 'NetTime') {
                $servico = Get-Service -Name 'NetTimeSvc' -ErrorAction SilentlyContinue
                if (-not $servico) {
                    Write-GuardianStatus 'NetTime: programa instalado, mas servico NetTimeSvc nao localizado; verificar instalacao no teste.' 'WARN'
                } elseif ($servico.Status -ne 'Running') {
                    Write-GuardianStatus ("NetTime: servico instalado, estado atual: {0}." -f $servico.Status) 'WARN'
                }
            }
        } else {
            Write-GuardianStatus ("{0}: instalador terminou, mas o programa nao foi confirmado no Windows." -f $Programa) 'WARN'
        }
    } catch {
        Write-GuardianStatus ("{0}: falha na preparacao: {1}. Guardian prossegue." -f $Programa, $_.Exception.Message) 'WARN'
    } finally {
        try { Remove-Item -LiteralPath $diretorio -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

if ((-not $ExecutaFases -or $ExecutaFases -contains 1) -and
    (-not $PulaFases -or $PulaFases -notcontains 1) -and -not $Simulado) {
    foreach ($programaOpcional in @('NetTime')) {
        try { Install-GuardianOptionalProgram -Programa $programaOpcional }
        catch { Write-GuardianStatus ("{0}: falha isolada: {1}" -f $programaOpcional, $_.Exception.Message) 'WARN' }
    }
}

# ===============================================================================
# DESINSTALACAO SILENCIOSA - transplante da rotina do IT4YOU-Checkup (6)
# Sem saida em modo normal. Exibe resultados apenas com -Debug.
# Nao altera a pontuacao, o JSON nem o resultado das fases.
# ===============================================================================
function Write-GuardianUninstallDebug([string]$Message) {
    if ($script:GuardianDebugMode) {
        Microsoft.PowerShell.Utility\Write-Host ('  [DESINSTALACAO] ' + $Message) -ForegroundColor DarkGray
    }
}
function Assert-GuardianUninstallTrue([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Invoke-GuardianUninstallExecutable([string]$Exe,[string]$Arguments,[int]$TimeoutSec=600,[int[]]$AllowedCodes=@(0,3010)) {
    Assert-GuardianUninstallTrue (Test-Path -LiteralPath $Exe) ('Arquivo nao encontrado: ' + $Exe)
    Write-GuardianUninstallDebug ('EXECUTAVEL {0} {1}' -f $Exe,$Arguments)
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
    $exitCode = $null
    try {
        if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch {}; throw ('Tempo limite excedido: '+$TimeoutSec+' segundos.') }
        $exitCode = $p.ExitCode
        Assert-GuardianUninstallTrue ($exitCode -in $AllowedCodes) ('Codigo de saida ' + $exitCode)
    } finally { $p.Dispose() }
    if ($exitCode -eq 3010) { Write-GuardianUninstallDebug 'Reinicializacao solicitada pelo desinstalador.' }
}
# ======================= DESINSTALACAO CONSERVADORA =========================
function Get-GuardianUninstallRecords {
  $locations=@(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $all=@(Get-ItemProperty -Path $locations -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and -not [string]::IsNullOrWhiteSpace([string]$_.PSObject.Properties['DisplayName'].Value) })
  # HKCU elevado nao representa necessariamente o usuario conectado.
  # Enumerar uninstall de usuarios com perfil carregado (sem carregar hives off-line).
  try {
    foreach ($sid in @(Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' })) {
      $path='Registry::HKEY_USERS\'+$sid.PSChildName+'\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
      $all+=@(Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and -not [string]::IsNullOrWhiteSpace([string]$_.PSObject.Properties['DisplayName'].Value) })
    }
  } catch { Write-GuardianUninstallDebug ('Aviso ao enumerar HKU: '+$_.Exception.Message) }
  @($all | Sort-Object PSPath -Unique)
}
function Get-GuardianUninstallMatches([string]$Regex) {
  @(Get-GuardianUninstallRecords | Where-Object { $_.PSObject.Properties['DisplayName'] -and [string]$_.PSObject.Properties['DisplayName'].Value -match $Regex })
}
function Get-GuardianQuietUninstall([object]$App) {
  $quiet=if ($App.PSObject.Properties['QuietUninstallString']) { [string]$App.PSObject.Properties['QuietUninstallString'].Value } else { '' }
  $normal=if ($App.PSObject.Properties['UninstallString']) { [string]$App.PSObject.Properties['UninstallString'].Value } else { '' }
  if ($quiet.Trim()) { return $quiet.Trim() }
  if ($normal -match '(?i)\bmsiexec(?:\.exe)?\b.*(?:\{|/I|/X)') { return $normal }
  return $null
}
function Split-GuardianUninstallCommand([string]$Command) {
  $m=[regex]::Match($Command,'^\s*(?:"([^"]+)"|(.+?\.exe))\s*(.*)$','IgnoreCase')
  if(-not $m.Success) { throw ('PENDENTE: Comando de desinstalacao invalido: '+$Command) }
  $exe=if($m.Groups[1].Success){$m.Groups[1].Value}else{$m.Groups[2].Value}
  $exe=[Environment]::ExpandEnvironmentVariables($exe.Trim())
  if($exe -notmatch '^(?:[a-zA-Z]:\\|\\\\)') { throw ('PENDENTE: Executavel de desinstalacao nao absoluto: '+$exe) }
  [pscustomobject]@{Exe=$exe;Arguments=$m.Groups[3].Value.Trim()}
}
function Get-GuardianApprovedUninstallCommand([object]$App) {
  $name=[string]$App.DisplayName
  $normal=if ($App.PSObject.Properties['UninstallString']) { [string]$App.PSObject.Properties['UninstallString'].Value } else { '' }
  $quiet=Get-GuardianQuietUninstall $App
  $msi=[regex]::Match(($quiet+' '+$normal),'\{[0-9a-fA-F-]{36}\}')
  if($msi.Success -and ($quiet+' '+$normal) -match '(?i)\bmsiexec') {
    return [pscustomobject]@{Exe="$env:windir\System32\msiexec.exe";Arguments=('/x '+$msi.Value+' /qn /norestart');ExitCodes=@(0,3010,1605,1614)}
  }
  # Preferir desinstalador registrado. Somente aplicar switches a executaveis reconhecidos.
  $parsed=$null
  if($normal.Trim()) { try {$parsed=Split-GuardianUninstallCommand $normal} catch {} }
  # Malwarebytes 5: mbuns.exe testado em PowerShell 7 elevado (5.7.3.376).
  # Parametros confirmados: codigo 0 e ausencia no registro apos remocao.
  # Aceitar o executavel registrado apenas quando o caminho for o produto Malwarebytes.
  if($name -match '(?i)^Malwarebytes(?:\s|$)' -and $parsed -and
     $parsed.Exe -match '(?i)\\Malwarebytes\\Anti-Malware\\mbuns\.exe$') {
    return [pscustomobject]@{Exe=$parsed.Exe;Arguments='-nosurvey -uninstall -silent';ExitCodes=@(0,3010)}
  }
  # O registro pode nao conter o caminho do desinstalador em algumas versoes.
  # Fallback restrito ao caminho oficial do produto, se o Malwarebytes estiver detectado.
  if($name -match '(?i)^Malwarebytes(?:\s|$)') {
    $mbuns=Join-Path $env:ProgramFiles 'Malwarebytes\Anti-Malware\mbuns.exe'
    if(Test-Path -LiteralPath $mbuns -PathType Leaf) {
      return [pscustomobject]@{Exe=$mbuns;Arguments='-nosurvey -uninstall -silent';ExitCodes=@(0,3010)}
    }
  }
  if($name -match '(?i)^Driver Booster(?:\s|$)' -and $parsed -and $parsed.Exe -match '(?i)\\unins\d*\.exe$' -and $parsed.Exe -match '(?i)\\IObit\\Driver Booster\\') {
    return [pscustomobject]@{Exe=$parsed.Exe;Arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART';ExitCodes=@(0,3010,1)}
  }
  if($name -match '(?i)^CCleaner(?:\s|$)' -and $parsed -and $parsed.Exe -match '(?i)\\Piriform\\Icarus\\piriform-ccl\\icarus\.exe$' -and $parsed.Arguments -match '(?i)/uninstall:piriform-ccl') {
    return [pscustomobject]@{Exe=$parsed.Exe;Arguments='/manual_update /uninstall:piriform-ccl /Silent';ExitCodes=@(0,3010)}
  }
  if($name -match '(?i)^CCleaner(?:\s|$)' -and $parsed -and $parsed.Exe -match '(?i)\\(?:uninst|uninstall)\.exe$' -and $parsed.Exe -match '(?i)\\CCleaner\\') {
    return [pscustomobject]@{Exe=$parsed.Exe;Arguments='/S';ExitCodes=@(0,3010)}
  }
  if(-not $quiet) { throw ('PENDENTE: Desinstalador silencioso nao identificado com seguranca: '+$name+'; comando registrado: '+$normal) }
  $command=Split-GuardianUninstallCommand $quiet
  return [pscustomobject]@{Exe=$command.Exe;Arguments=$command.Arguments;ExitCodes=@(0,3010)}
}
function Invoke-GuardianQuietUninstall([object]$App) {
  $command=Get-GuardianApprovedUninstallCommand $App
  Invoke-GuardianUninstallExecutable $command.Exe $command.Arguments 1200 $command.ExitCodes
  # Alguns desinstaladores (especialmente IObit) devolvem 1 mesmo quando removem.
  # A confirmacao definitiva e a ausencia do mesmo registro apos a execucao.
}
function Remove-GuardianApprovedApps([string]$Regex) {
  $targets=@(Get-GuardianUninstallMatches $Regex)
  if ($targets.Count -eq 0) { Write-GuardianUninstallDebug ('NAO ENCONTRADO: '+$Regex); return }
  $issues=New-Object System.Collections.Generic.List[string]
  foreach ($app in $targets) {
    $name=[string]$app.DisplayName
    Write-GuardianUninstallDebug ('IDENTIFICADO: '+$name)
    try {
      Invoke-GuardianQuietUninstall $app
      $present=@()
      foreach($attempt in 1..8) {
        Start-Sleep -Seconds 3
        $present=@(Get-GuardianUninstallRecords | Where-Object { $_.PSPath -eq $app.PSPath })
        if($present.Count -eq 0){break}
      }
      if ($present.Count -gt 0) { throw ('Desinstalador finalizou sem remocao confirmada: '+$name) }
      Write-GuardianUninstallDebug ('REMOVIDO '+$name)
    } catch { Write-GuardianUninstallDebug ('FALHA '+$name+': '+$_.Exception.Message); $issues.Add($name+': '+$_.Exception.Message) }
  }
  if ($issues.Count -gt 0) { throw ('PENDENTE: '+($issues -join ' | ')) }
}
function Remove-GuardianMalwarebytesAll {
  # A execucao deste Checkup e autorizacao operacional para remover o Malwarebytes
  # independentemente da licenca (Free, Trial ou Premium).
  # Para produtos sem desinstalador silencioso conhecido, informar pendencia;
  # nao adivinhar switches nem remover arquivos de protecao manualmente.
  Remove-GuardianApprovedApps '(?i)^Malwarebytes(?:\s|$)'
}

# Higienizacao pos-desinstalacao, restrita a artefatos exclusivos dos produtos aprovados.
# Nao remove perfis, dados de usuario, drivers, servicos ou diretorios nao vazios.
function Test-GuardianUninstallProductAbsent([string]$Regex) {
    return (@(Get-GuardianUninstallMatches $Regex).Count -eq 0)
}
function Remove-GuardianSafeShortcut([string]$Path,[string]$NamePattern,[string]$TargetPattern) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    if ([IO.Path]::GetExtension($Path) -ine '.lnk') { return }
    $shortcutName = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($shortcutName -notmatch $NamePattern) { return }
    try {
        $shell=New-Object -ComObject WScript.Shell -ErrorAction Stop
        $lnk=$shell.CreateShortcut($Path)
        $target=[string]$lnk.TargetPath
        if ($target -notmatch $TargetPattern) {
            Write-GuardianUninstallDebug ('RESIDUO IGNORADO (atalho com destino divergente): '+$Path)
            return
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-GuardianUninstallDebug ('RESIDUO REMOVIDO (atalho): '+$Path)
    } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (atalho): '+$Path+' - '+$_.Exception.Message) }
}
function Remove-GuardianApprovedShortcuts([string]$NamePattern,[string]$TargetPattern) {
    $roots=@(
      [Environment]::GetFolderPath('CommonDesktopDirectory'),
      [Environment]::GetFolderPath('DesktopDirectory'),
      [Environment]::GetFolderPath('CommonPrograms'),
      [Environment]::GetFolderPath('Programs')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    foreach($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        try {
            # Nao percorre outras pastas de perfis nem discos inteiros.
            foreach($f in @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction Stop)) {
                Remove-GuardianSafeShortcut $f.FullName $NamePattern $TargetPattern
            }
        } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (atalhos): '+$root+' - '+$_.Exception.Message) }
    }
}
function Remove-GuardianCcleanerRecycleBinMenuKeys([string]$HiveRoot) {
    # Em cada perfil, nao remover integracoes enquanto houver CCleaner registrado
    # nesse proprio perfil. Nao depende do usuario atual nem de SID fixo.
    $uninstallPath=$HiveRoot+'\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $installed=@(Get-ItemProperty -Path $uninstallPath -ErrorAction SilentlyContinue | Where-Object {
        $_.PSObject.Properties['DisplayName'] -and
        [string]$_.PSObject.Properties['DisplayName'].Value -match '(?i)^CCleaner(?:\s|$)'
    })
    if($installed.Count -gt 0) {
        Write-GuardianUninstallDebug ('RESIDUO PRESERVADO (CCleaner registrado no perfil): '+$HiveRoot)
        return
    }
    $id='{645FF040-5081-101B-9F08-00AA002F954E}'
    $shellRoot=$HiveRoot+'\Software\Classes\CLSID\'+$id+'\Shell'
    foreach($name in @('CCleaner.CleanRecycleBin','CCleaner.RunAnalysis')) {
        $key=$shellRoot+'\'+$name
        if(-not (Test-Path -LiteralPath $key)) { continue }
        try {
            $commandKey=$key+'\command'
            if(-not (Test-Path -LiteralPath $commandKey)) { continue }
            $command=[string](Get-Item -LiteralPath $commandKey -ErrorAction Stop).GetValue('')
            # Exatamente os dois comandos de Lixeira identificados no diagnostico.
            # Nao tocar em 'empty' (Windows), nem em comandos de terceiros.
            if($command -notmatch '(?i)\\CCleaner(?:64)?\.exe(?="|\s|$)') {
                Write-GuardianUninstallDebug ('RESIDUO PRESERVADO (comando divergente): '+$key)
                continue
            }
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            Write-GuardianUninstallDebug ('RESIDUO REMOVIDO (menu Lixeira): '+$key)
        } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (menu Lixeira): '+$key+' - '+$_.Exception.Message) }
    }
}
function Remove-GuardianCcleanerRecycleBinMenu {
    # HKLM e todos os perfis locais registrados; sem nomes ou SIDs fixos.
    # Perfis descarregados sao montados temporariamente, apenas se acessiveis.
    $id='{645FF040-5081-101B-9F08-00AA002F954E}'
    $machineShell='Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\'+$id+'\Shell'
    foreach($name in @('CCleaner.CleanRecycleBin','CCleaner.RunAnalysis')) {
        $key=$machineShell+'\'+$name
        if(-not (Test-Path -LiteralPath $key)) { continue }
        try {
            $commandKey=$key+'\command'
            if(-not (Test-Path -LiteralPath $commandKey)) { continue }
            $command=[string](Get-Item -LiteralPath $commandKey -ErrorAction Stop).GetValue('')
            if($command -notmatch '(?i)\\CCleaner(?:64)?\.exe(?="|\s|$)') { continue }
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            Write-GuardianUninstallDebug ('RESIDUO REMOVIDO (menu Lixeira global): '+$key)
        } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (menu Lixeira global): '+$key+' - '+$_.Exception.Message) }
    }
    $profiles='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $n=0
    foreach($profile in @(Get-ChildItem -LiteralPath $profiles -ErrorAction SilentlyContinue)) {
        $sid=[string]$profile.PSChildName
        if($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { continue }
        $hiveRoot='Registry::HKEY_USERS\'+$sid
        if(Test-Path -LiteralPath $hiveRoot) {
            try { Remove-GuardianCcleanerRecycleBinMenuKeys $hiveRoot }
            catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (perfil '+$sid+'): '+$_.Exception.Message) }
            continue
        }
        $mounted=$false
        $tempName=$null
        try {
            $profileInfo=Get-ItemProperty -LiteralPath $profile.PSPath -ErrorAction Stop
            $profileDirectory=[Environment]::ExpandEnvironmentVariables([string]$profileInfo.ProfileImagePath)
            if([string]::IsNullOrWhiteSpace($profileDirectory)) { continue }
            $hiveFile=Join-Path $profileDirectory 'NTUSER.DAT'
            if(-not (Test-Path -LiteralPath $hiveFile -PathType Leaf)) { continue }
            $n++
            $tempName='GuardianCC_'+$PID+'_'+$n
            $null=& "$env:WINDIR\System32\reg.exe" load ('HKU\'+$tempName) $hiveFile 2>&1
            if($LASTEXITCODE -ne 0) {
                Write-GuardianUninstallDebug ('RESIDUO PENDENTE (perfil indisponivel): '+$sid)
                continue
            }
            $mounted=$true
            Remove-GuardianCcleanerRecycleBinMenuKeys ('Registry::HKEY_USERS\'+$tempName)
        } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (perfil '+$sid+'): '+$_.Exception.Message) }
        finally {
            if($mounted -and $tempName) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                $null=& "$env:WINDIR\System32\reg.exe" unload ('HKU\'+$tempName) 2>&1
                if($LASTEXITCODE -ne 0) {
                    Write-GuardianUninstallDebug ('RESIDUO PENDENTE (hive carregado, descarregamento falhou): '+$tempName)
                }
            }
        }
    }
}
function Remove-GuardianApprovedEmptyFolders([string[]]$Folders) {
    foreach($folder in $Folders) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        # Pastas explicitamente definidas abaixo; apenas quando estiverem realmente vazias.
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        try {
            $children=@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)
            if($children.Count -eq 0) {
                Remove-Item -LiteralPath $folder -Force -ErrorAction Stop
                Write-GuardianUninstallDebug ('RESIDUO REMOVIDO (pasta vazia): '+$folder)
            } else { Write-GuardianUninstallDebug ('RESIDUO PRESERVADO (pasta com conteudo): '+$folder) }
        } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (pasta): '+$folder+' - '+$_.Exception.Message) }
    }
}
function Remove-GuardianApprovedOrphanTasks([string]$TaskNamePattern,[string]$TargetPattern) {
    # Somente tarefas do produto cujo executavel tenha desaparecido do disco.
    try {
        foreach($task in @(Get-ScheduledTask -ErrorAction Stop)) {
            if ([string]$task.TaskName -notmatch $TaskNamePattern) { continue }
            $actions=@($task.Actions | Where-Object { $null -ne $_ })
            if($actions.Count -ne 1) { continue }
            if (-not $actions[0].PSObject.Properties['Execute']) { continue }
            $exe=[string]$actions[0].PSObject.Properties['Execute'].Value
            if($exe -notmatch $TargetPattern) { continue }
            $expanded=[Environment]::ExpandEnvironmentVariables($exe.Trim('"'))
            if($expanded -notmatch '^(?:[a-zA-Z]:\\|\\\\)') { continue }
            if(Test-Path -LiteralPath $expanded -PathType Leaf) { continue }
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                Write-GuardianUninstallDebug ('RESIDUO REMOVIDO (tarefa orfa): '+$task.TaskPath+$task.TaskName)
            } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (tarefa): '+$task.TaskName+' - '+$_.Exception.Message) }
        }
    } catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE (tarefas): '+$_.Exception.Message) }
}
function Invoke-GuardianKnownResidueCleanup([string]$Product) {
    $rules=@{
      'CCleaner' = @{ Reg='(?i)^CCleaner(?:\s|$)'; Shortcut='(?i)^CCleaner(?:\s|$)'; Target='(?i)\\(?:CCleaner|Piriform)\\|ccleaner(?:64)?\.exe$'; Folders=@("${env:ProgramFiles}\CCleaner", "${env:ProgramFiles(x86)}\CCleaner"); Task='(?i)^CCleaner(?:\s|$)' }
      'CPUID CPU-Z / HWMonitor' = @{ Reg='(?i)^(?:CPUID\s+)?(?:CPU-Z|HWMonitor)(?:\s|$)'; Shortcut='(?i)^(?:CPUID\s+)?(?:CPU-Z|HWMonitor)(?:\s|$)'; Target='(?i)\\(?:CPUID|CPU-Z|HWMonitor)\\|\\(?:cpuz|hwmonitor)(?:_x64)?\.exe$'; Folders=@("${env:ProgramFiles}\CPUID", "${env:ProgramFiles(x86)}\CPUID"); Task='(?i)^(?:CPUID\s+)?(?:CPU-Z|HWMonitor)(?:\s|$)' }
      'CrystalDiskInfo' = @{ Reg='(?i)^CrystalDiskInfo(?:\s|$)'; Shortcut='(?i)^CrystalDiskInfo(?:\s|$)'; Target='(?i)\\CrystalDiskInfo\\|\\DiskInfo(?:64)?\.exe$'; Folders=@("${env:ProgramFiles}\CrystalDiskInfo"); Task='(?i)^CrystalDiskInfo(?:\s|$)' }
      'CrystalDiskMark' = @{ Reg='(?i)^CrystalDiskMark(?:\s|$)'; Shortcut='(?i)^CrystalDiskMark(?:\s|$)'; Target='(?i)\\CrystalDiskMark\d*\\|\\DiskMark(?:64)?\.exe$'; Folders=@("${env:ProgramFiles}\CrystalDiskMark", "${env:ProgramFiles}\CrystalDiskMark9"); Task='(?i)^CrystalDiskMark(?:\s|$)' }
      'Driver Booster' = @{ Reg='(?i)^Driver Booster(?:\s|$)'; Shortcut='(?i)^Driver Booster(?:\s|$)'; Target='(?i)\\IObit\\Driver Booster\\'; Folders=@("${env:ProgramFiles(x86)}\IObit\Driver Booster", "${env:ProgramFiles}\IObit\Driver Booster"); Task='(?i)^Driver Booster(?:\s|$)' }
      'MiniTool Partition Wizard' = @{ Reg='(?i)^MiniTool Partition Wizard(?:\s|$)'; Shortcut='(?i)^MiniTool Partition Wizard(?:\s|$)'; Target='(?i)\\MiniTool Partition Wizard\\|\\MiniTool\\'; Folders=@("${env:ProgramFiles}\MiniTool Partition Wizard", "${env:ProgramFiles(x86)}\MiniTool Partition Wizard"); Task='(?i)^MiniTool Partition Wizard(?:\s|$)' }
      'Revo Uninstaller' = @{ Reg='(?i)^Revo Uninstaller(?:\s|$)'; Shortcut='(?i)^Revo Uninstaller(?:\s|$)'; Target='(?i)\\VS Revo Group\\Revo Uninstaller\\|\\Revo Uninstaller\\'; Folders=@("${env:ProgramFiles}\VS Revo Group\Revo Uninstaller", "${env:ProgramFiles(x86)}\VS Revo Group\Revo Uninstaller"); Task='(?i)^Revo Uninstaller(?:\s|$)' }
      'Malwarebytes' = @{ Reg='(?i)^Malwarebytes(?:\s|$)'; Shortcut='(?i)^Malwarebytes(?:\s|$)'; Target='(?i)\\Malwarebytes\\'; Folders=@("${env:ProgramFiles}\Malwarebytes", "${env:ProgramFiles(x86)}\Malwarebytes"); Task='(?i)^Malwarebytes(?:\s|$)' }
    }
    if(-not $rules.ContainsKey($Product)) { return }
    $rule=$rules[$Product]
    if(-not (Test-GuardianUninstallProductAbsent $rule.Reg)) {
        Write-GuardianUninstallDebug ('RESIDUO PRESERVADO (produto ainda instalado): '+$Product)
        return
    }
    Write-GuardianUninstallDebug ('Verificando residuos conhecidos: '+$Product)
    if($Product -eq 'CCleaner') { Remove-GuardianCcleanerRecycleBinMenu }
    Remove-GuardianApprovedShortcuts $rule.Shortcut $rule.Target
    Remove-GuardianApprovedOrphanTasks $rule.Task $rule.Target
    Remove-GuardianApprovedEmptyFolders $rule.Folders
}

# Substituicao de compactadores: instalar e confirmar PeaZip pt-BR ANTES de
# retirar 7-Zip/WinRAR. Isolada das demais remocoes e das notas da vistoria.
function Get-GuardianPeaZipExe {
    $paths = @((Join-Path $env:ProgramFiles 'PeaZip\peazip.exe'))
    if (${env:ProgramFiles(x86)}) { $paths += (Join-Path ${env:ProgramFiles(x86)} 'PeaZip\peazip.exe') }
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    return $null
}
# Configuracao efetiva do idioma: o instalador define pt-BR, mas perfis que
# ja usaram PeaZip podem manter uma preferencia anterior em ingles.
# O arquivo conf.txt possui a secao [language] seguida do nome da traducao.
# Ajusta apenas esse valor, preservando todas as demais preferencias.
function Set-GuardianPeaZipPtBR {
    $exe = Get-GuardianPeaZipExe
    if (-not $exe) { throw 'PeaZip nao instalado.' }
    $installDir = Split-Path -Path $exe -Parent
    $languageFiles = @(
        (Join-Path $installDir 'res\share\lang\pt-br.txt'),
        (Join-Path $installDir 'res\lang\pt-br.txt')
    )
    if (-not @($languageFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count) {
        throw 'Traducao pt-br.txt nao encontrada na instalacao do PeaZip.'
    }
    # Nao alterar preferencias com o PeaZip aberto: ele poderia grava-las
    # novamente em ingles ao fechar.
    if (@(Get-Process -Name 'peazip' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'PeaZip em execucao; ajuste de idioma adiado ate o aplicativo ser fechado.'
    }
    $configPaths = New-Object 'System.Collections.Generic.List[string]'
    # Configuracao compartilhada/default para perfis que ainda nao abriram o app.
    $configPaths.Add((Join-Path $installDir 'res\conf\conf.txt'))
    $configPaths.Add((Join-Path $installDir 'res\conf.txt'))
    # Percorre os perfis reais do Windows sem depender do nome da conta,
    # inclusive quando o Guardian foi elevado com outra conta administrativa.
    try {
        $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = False' -ErrorAction Stop)
    } catch {
        throw ('Nao foi possivel enumerar os perfis para validar o idioma: ' + $_.Exception.Message)
    }
    foreach ($profile in $profiles) {
        $profilePath = [string]$profile.LocalPath
        if ([string]::IsNullOrWhiteSpace($profilePath) -or -not (Test-Path -LiteralPath $profilePath -PathType Container)) { continue }
        $configPaths.Add((Join-Path $profilePath 'AppData\Roaming\PeaZip\conf.txt'))
        $configPaths.Add((Join-Path $profilePath 'AppData\Roaming\PeaZip\res\conf\conf.txt'))
    }
    $checked = 0
    $modified = 0
    $languageMarker = [regex]'(?m)^\[language\]\r?\n([^\r\n]*)'
    foreach ($config in @($configPaths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { continue }
        $checked++
        try {
            $content = [System.IO.File]::ReadAllText($config)
            $match = $languageMarker.Match($content)
            if (-not $match.Success) { throw 'secao [language] nao encontrada' }
            $oldValue = $match.Groups[1].Value
            if ($oldValue -cne 'pt-br.txt') {
                $position = $match.Groups[1].Index
                $updated = $content.Substring(0,$position) + 'pt-br.txt' + $content.Substring($position + $oldValue.Length)
                [System.IO.File]::WriteAllText($config,$updated,(New-Object System.Text.UTF8Encoding($true)))
                $modified++
            }
            $verified = [System.IO.File]::ReadAllText($config)
            $verifyMatch = $languageMarker.Match($verified)
            if (-not $verifyMatch.Success -or $verifyMatch.Groups[1].Value -cne 'pt-br.txt') {
                throw 'validacao apos gravacao falhou'
            }
        } catch {
            throw ('Idioma pt-BR nao confirmado em {0}: {1}' -f $config,$_.Exception.Message)
        }
    }
    Write-GuardianUninstallDebug ('PeaZip pt-BR: traducao presente; configuracoes verificadas {0}; ajustadas {1}.' -f $checked,$modified)
}
function Install-GuardianPeaZipPtBR {
    if (Get-GuardianPeaZipExe) {
        Write-GuardianUninstallDebug 'PeaZip ja instalado; verificando configuracao de idioma.'
        return
    }
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) { throw 'Winget indisponivel; compactadores antigos preservados.' }
    # Instalador oficial selecionado pelo catalogo Winget; /PT-BR ao final do override.
    $arguments = 'install --id Giorgiotani.Peazip --exact --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements --no-upgrade --override "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PT-BR"'
    $issues = New-Object 'System.Collections.Generic.List[string]'
    for ($attempt=1; $attempt -le 3; $attempt++) {
        if (Get-GuardianPeaZipExe) { return }
        try {
            Write-GuardianUninstallDebug ('PeaZip pt-BR: tentativa de instalacao {0}/3.' -f $attempt)
            $p = Start-Process -FilePath $winget.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
            try {
                if (-not $p.WaitForExit(1200000)) {
                    try { $p.Kill() } catch { }
                    throw 'Tempo limite de instalacao excedido.'
                }
                $code = [int64]$p.ExitCode
            } finally { $p.Dispose() }
            if ($code -notin @(0,3010)) { throw ('Winget retornou codigo ' + $code) }
            for ($i=0; $i -lt 10; $i++) {
                if (Get-GuardianPeaZipExe) {
                    Write-GuardianUninstallDebug 'PeaZip pt-BR instalado e executavel confirmado.'
                    return
                }
                Start-Sleep -Seconds 2
            }
            throw 'Executavel PeaZip nao localizado apos a instalacao.'
        } catch {
            $issues.Add(('Tentativa {0}/3: {1}' -f $attempt,$_.Exception.Message))
            if ($attempt -lt 3) { Start-Sleep -Seconds (10 * $attempt) }
        }
    }
    throw ('PeaZip nao instalado; 7-Zip e WinRAR preservados. ' + ($issues -join ' | '))
}
function Remove-GuardianLegacyArchivers {
    # Nao desinstalar compactadores sem ter confirmado o substituto.
    if (-not (Get-GuardianPeaZipExe)) { throw 'PeaZip ausente; 7-Zip e WinRAR preservados.' }
    $records = @(Get-GuardianUninstallMatches '(?i)^(?:7-Zip|WinRAR)(?:\s|$)')
    foreach ($app in $records) {
        $name = [string]$app.PSObject.Properties['DisplayName'].Value
        $normal = if ($app.PSObject.Properties['UninstallString']) { [string]$app.PSObject.Properties['UninstallString'].Value } else { '' }
        $quiet = if ($app.PSObject.Properties['QuietUninstallString']) { [string]$app.PSObject.Properties['QuietUninstallString'].Value } else { '' }
        $exe = $null; $args = $null
        $msi = [regex]::Match(($quiet + ' ' + $normal),'\{[0-9a-fA-F-]{36}\}')
        if ($msi.Success -and ($quiet + ' ' + $normal) -match '(?i)\bmsiexec') {
            $exe = Join-Path $env:windir 'System32\msiexec.exe'
            $args = '/x ' + $msi.Value + ' /qn /norestart'
        } elseif ($name -match '(?i)^7-Zip(?:\s|$)' -and
                  $normal -match '(?i)^\s*"?([A-Z]:\\[^"\r\n]*\\7-Zip\\Uninstall\.exe)"?') {
            $exe = $Matches[1]; $args = '/S'
        } elseif ($name -match '(?i)^WinRAR(?:\s|$)' -and
                  $normal -match '(?i)^\s*"?([A-Z]:\\[^"\r\n]*\\WinRAR\\Uninstall\.exe)"?') {
            $exe = $Matches[1]; $args = '/S'
        } elseif ($quiet -match '(?i)^\s*"([A-Z]:\\[^"\r\n]+\.exe)"\s+(.+)$') {
            $exe = $Matches[1]; $args = $Matches[2]
        }
        if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
            Write-GuardianUninstallDebug ('PENDENTE '+$name+': desinstalador silencioso nao confirmado.')
            continue
        }
        try {
            Invoke-GuardianUninstallExecutable -Exe $exe -Arguments $args -TimeoutSec 600 -AllowedCodes @(0,3010,1605,1614)
            $stillPresent = $true
            for ($i=0; $i -lt 8; $i++) {
                Start-Sleep -Seconds 2
                $stillPresent = (@(Get-GuardianUninstallMatches ('(?i)^'+[regex]::Escape($name)+'$') |
                    Where-Object { $_.PSPath -eq $app.PSPath }).Count -gt 0)
                if (-not $stillPresent) { break }
            }
            if ($stillPresent) { throw 'Registro de instalacao ainda presente.' }
            Write-GuardianUninstallDebug ('REMOVIDO: '+$name)
        } catch {
            Write-GuardianUninstallDebug ('PENDENTE '+$name+': '+$_.Exception.Message)
        }
    }
}
function Invoke-GuardianPeaZipMigration {
    try {
        Install-GuardianPeaZipPtBR
        Set-GuardianPeaZipPtBR
        Remove-GuardianLegacyArchivers
    } catch {
        Write-GuardianUninstallDebug ('PENDENTE PeaZip: '+$_.Exception.Message)
    }
}

# Microsoft PC Manager: instalacao opcional e silenciosa antes da Fase 1.
# Nao altera configuracoes do aplicativo, outras fases ou pontuacao.
function Test-GuardianPCManagerInstalled {
    try {
        $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop |
            Where-Object { $_.Name -match '(?i)^Microsoft\.(?:Microsoft)?PCManager$' })
        if ($packages.Count -gt 0) { return $true }
    } catch {
        Write-GuardianUninstallDebug ('PC Manager: consulta Appx indisponivel: ' + $_.Exception.Message)
    }
    foreach ($root in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        foreach ($entry in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            $name = if ($entry.PSObject.Properties['DisplayName']) { [string]$entry.DisplayName } else { '' }
            if ($name -match '(?i)^(?:Microsoft\s+)?PC\s*Manager(?:\s|$)') { return $true }
        }
    }
    return $false
}

function Install-GuardianPCManager {
    if (Test-GuardianPCManagerInstalled) {
        Write-GuardianUninstallDebug 'PC Manager: ja instalado; nenhuma acao necessaria.'
        return
    }
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        Write-GuardianUninstallDebug 'PC Manager: Winget indisponivel; instalacao ignorada.'
        return
    }

    # ID oficial do produto na Microsoft Store, nao o pacote Beta antigo.
    $arguments = 'install --id 9PM860492SZD --exact --source msstore --silent --disable-interactivity --accept-package-agreements --accept-source-agreements --no-upgrade'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (Test-GuardianPCManagerInstalled) { return }
        try {
            Write-GuardianUninstallDebug ('PC Manager: tentativa de instalacao {0}/3.' -f $attempt)
            $process = Start-Process -FilePath $winget.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden -ErrorAction Stop
            if (-not $process.WaitForExit(240000)) {
                try { $process.Kill() } catch { }
                throw 'Winget excedeu 240 segundos.'
            }
            $code = $process.ExitCode
            for ($check = 0; $check -lt 6; $check++) {
                if (Test-GuardianPCManagerInstalled) {
                    Write-GuardianUninstallDebug 'PC Manager: instalacao confirmada.'
                    return
                }
                Start-Sleep -Seconds 2
            }
            throw ('Instalacao nao confirmada; codigo Winget: {0}.' -f $code)
        } catch {
            Write-GuardianUninstallDebug ('PC Manager: tentativa {0}/3 falhou: {1}' -f $attempt,$_.Exception.Message)
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds (10 * $attempt) }
    }
    Write-GuardianUninstallDebug 'PC Manager: instalacao pendente; Guardian prossegue normalmente.'
}

function Invoke-GuardianAppCleanup {
    Write-GuardianUninstallDebug 'Iniciando verificacao de aplicativos.'
    Invoke-GuardianPeaZipMigration
    try { Install-GuardianPCManager }
    catch { Write-GuardianUninstallDebug ('PC Manager: falha isolada: ' + $_.Exception.Message) }
    $remove=@(
        @('CCleaner','(?i)^CCleaner(?:\s|$)'),
        @('CPUID CPU-Z / HWMonitor','(?i)^(?:CPUID\s+)?(?:CPU-Z|HWMonitor)(?:\s|$)'),
        @('CrystalDiskInfo','(?i)^CrystalDiskInfo(?:\s|$)'),
        @('CrystalDiskMark','(?i)^CrystalDiskMark(?:\s|$)'),
        @('Driver Booster','(?i)^Driver Booster(?:\s|$)'),
        @('MiniTool Partition Wizard','(?i)^MiniTool Partition Wizard(?:\s|$)'),
        @('Revo Uninstaller','(?i)^Revo Uninstaller(?:\s|$)')
    )
    foreach ($item in $remove) {
        $nome=[string]$item[0]
        $regex=[string]$item[1]
        try { Remove-GuardianApprovedApps $regex }
        catch { Write-GuardianUninstallDebug ('PENDENTE '+$nome+': '+$_.Exception.Message) }
        try { Invoke-GuardianKnownResidueCleanup $nome }
        catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE '+$nome+': '+$_.Exception.Message) }
    }
    # Excecoes baseadas estritamente no nome do computador (independentemente do cliente).
    if ($env:COMPUTERNAME -in @('JDAC-NB14','INOVATEC-NB21')) {
        Write-GuardianUninstallDebug ('PRESERVADO: Malwarebytes no computador '+$env:COMPUTERNAME)
    } else {
        try { Remove-GuardianMalwarebytesAll }
        catch { Write-GuardianUninstallDebug ('PENDENTE Malwarebytes: '+$_.Exception.Message) }
        try { Invoke-GuardianKnownResidueCleanup 'Malwarebytes' }
        catch { Write-GuardianUninstallDebug ('RESIDUO PENDENTE Malwarebytes: '+$_.Exception.Message) }
    }
    Write-GuardianUninstallDebug 'Verificacao encerrada.'
}

# Uma unica chamada, antes do inventario, apenas em execucao real da Fase 1.
if (-not $Simulado -and @($script:GuardianSelectedPhases | Where-Object { $_.Id -eq 1 }).Count -gt 0) {
    try { Invoke-GuardianAppCleanup }
    catch { Write-GuardianUninstallDebug ('PENDENTE limpeza: '+$_.Exception.Message) }
}

# === Loop principal com atualização da UI ===
foreach ($phase in $script:GuardianSelectedPhases) {
    $id = [int]$phase.Id
    $CurrentPhaseOrdinal++

    # Atualiza UI com fase atual
# v2 console: nao ha controle WPF nesta etapa.

    DoEvents

    Write-Host ""
    Show-Phase -Id $phase.Id -Title $phase.Title
    Send-GuardianLiveEvent -Type 'phase' -Label ('Tarefa {0:00} de {1:00} · {2}' -f $CurrentPhaseOrdinal, $script:GuardianPhaseCount, $phase.Title) -Percent ([int][Math]::Floor((($CurrentPhaseOrdinal - 1) / [Math]::Max(1,$script:GuardianPhaseCount)) * 95))
    Write-GuardianStatus ("=== Fase {0}: {1} ===" -f $phase.Id, $phase.Title) 'INFO'

    # Executa cada passo da fase
    foreach ($step in $phase.Steps) {
        # Atualiza UI com nome do passo atual e progresso
        $CurrentStep++
# v2 console: nao ha controle WPF nesta etapa.

        DoEvents

        # Atualiza a atividade antes de executar a funcao, preservando o progresso ao final.
        Send-GuardianLiveEvent -Type 'activity' -Label (Get-StepLabel $step.Name)

        # Executa o passo
        Invoke-GuardianStep -Title $step.Name -Action $step.Action
        Send-GuardianLiveEvent -Type 'step' -Label $step.Name -Percent ([int][Math]::Min(95,[Math]::Floor(($CurrentStep / [Math]::Max(1,$TotalSteps)) * 95)))

        # Inventario complementar; falhas nesta leitura nao interrompem a manutencao.
        # Dados somente para a WPF: leitura passiva, sem mudar o inventario/API/JSON.
        if ($id -eq 1 -and $step.Name -eq 'Get-SystemInventory' -and $script:GuardianUiAvailable) {
            try {
                $cpuInfo = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
                $csInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                $gpuInfo = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\s*USB Mobile Monitor Virtual Display\s*$' } | Select-Object -First 1
                $partition = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
                $osDisk = if ($partition) { $partition | Get-Disk -ErrorAction SilentlyContinue }
                $driveText = if ($osDisk) { '{0} · {1:N0} GB' -f ([string]$osDisk.FriendlyName -replace '^\s*ATA\s+', ''), ($osDisk.Size / 1GB) } else { 'Não identificado' }
                $ramText = if ($csInfo.TotalPhysicalMemory) { '{0:N0} GB' -f [Math]::Round(($csInfo.TotalPhysicalMemory / 1GB), 0, [MidpointRounding]::AwayFromZero) } else { 'Não disponível' }
                $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                $displayVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
                $osVersion = if ($displayVersion) { [string]$displayVersion } elseif ($osInfo) { [string]$osInfo.Version } else { '' }
                $osText = if ($osInfo) { ('{0} · {1}' -f $osInfo.Caption, $osVersion).TrimEnd(' ', '·') } else { 'Não disponível' }
                Send-GuardianLiveEvent -Type 'inventory' -Data @{
                    cpu = if ($cpuInfo.Name) { [string]$cpuInfo.Name } else { 'Não disponível' }
                    ram = $ramText
                    gpu = if ($gpuInfo.Name) { [string]$gpuInfo.Name } else { 'Não disponível' }
                    storage = $driveText
                    os = $osText
                }
            } catch { } # O painel complementar nunca interrompe a manutencao.
        }

        if ($id -eq 1 -and $step.Name -eq 'Get-SystemInventory') {
            try {
                $script:TeamViewerInfo = Get-GuardianTeamViewerInfo
                if ($script:TeamViewerInfo.Instalado) {
                    $tvLabel = if ($script:TeamViewerInfo.ID) { $script:TeamViewerInfo.ID } else { 'indisponivel' }
                }
            } catch {
                $script:TeamViewerInfo = [pscustomobject]@{
                    Instalado = $false; ID = $null; Versao = $null; Status = 'ErroLeitura'
                }

            }
        }

        # Atualiza barra de progresso proporcional
# v2 console: nao ha controle WPF nesta etapa.

        DoEvents
    }

    #if ($id -eq 5 -and (Get-RebootPending)) {
    #    Write-GuardianStatus 'Reinicialização pendente detectada após Atualizações.' 'WARN'
    #    Write-Host ("{0}› Uma reinicialização está pendente. Ela pode ser realizada fora desta janela de manutenção.{1}" -f $Yellow, $Reset)
    #}
}


#===========================================================================================================================================================



# 6) Preparar resultados estruturados; o resumo visual sera apresentado
# somente no FINAL do bloco finally, apos JSON, API e agendamentos.
# Inicializa array para JSON
$jsonResults = @()

foreach ($r in $global:Results) {

    # Segurança: valores padrão caso alguma propriedade esteja ausente
    $etapa    = if ($r.PSObject.Properties['Etapa']) { $r.Etapa } `
                elseif ($r.PSObject.Properties['Phase']) { $r.Phase } `
                else { "Etapa desconhecida" }

    $sucesso  = if ($r.PSObject.Properties['Sucesso']) { $r.Sucesso } `
                elseif ($r.PSObject.Properties['Status'])  { $r.Status -eq 'OK' } `
                else { $false }

    $tempo    = if ($r.PSObject.Properties['Tempo'])    { $r.Tempo } `
                elseif ($r.PSObject.Properties['TempoSeg']) { New-TimeSpan -Seconds $r.TempoSeg } `
                else { New-TimeSpan -Seconds 0 }

    $mensagem = if ($r.PSObject.Properties['Mensagem']) { $r.Mensagem } else { "" }

    $statusPlain = if ($sucesso) { 'OK' } else { 'ALERTA' }

    # Adiciona resultado seguro ao array do JSON
    $jsonResults += [PSCustomObject]@{
        Phase    = $etapa        # No JSON final, você mantém Phase
        Status   = $statusPlain
        TempoSeg = [math]::Round($tempo.TotalSeconds, 2)
        Mensagem = $mensagem
    }
}


# Confirma o backup do Macrium (se a função estiver presente)
if (Get-Command Confirm-MacriumBackup -ErrorAction SilentlyContinue) { Confirm-MacriumBackup 6>$null }

# O cronometro sera interrompido somente apos todas as tarefas finais.
# Resultado consolidado em memoria; mensagem tecnica omitida do console.



# ============================================================================== 
# Criação do JSON local seguindo a mesma lógica do log
$baseJsonDir  = Join-Path $root 'Json'
$year         = Get-Date -Format 'yyyy'
$monthNumber  = Get-Date -Format 'MM'
$monthName    = (Get-Culture).DateTimeFormat.GetMonthName([int]$monthNumber)
$monthFolder  = ("{0}. {1}" -f $monthNumber, (Get-Culture).TextInfo.ToTitleCase($monthName.ToLower()))
$jsonDir      = Join-Path (Join-Path $baseJsonDir $year) $monthFolder

# Cria diretório se não existir
if (-not (Test-Path $jsonDir)) { New-Item -Path $jsonDir -ItemType Directory -Force | Out-Null }

# Nome do arquivo JSON
$jsonFileName = "{0}_{1:yyyyMMdd_HHmm}.json" -f $env:COMPUTERNAME, (Get-Date)
$jsonFilePath = Join-Path $jsonDir $jsonFileName

# Monta objeto final seguro
$jsonObject = [PSCustomObject]@{
    Cliente            = if ($Cliente) { $Cliente } else { "Não informado" }
    NomeComputador     = $env:COMPUTERNAME
    DataExecucao       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    PulaFases          = @($PulaFases)
    TeamViewer         = $script:TeamViewerInfo
    Fases              = $jsonResults
}

# O objeto permanece em memoria; consolidacao e serializacao ocorrem no finally.
$script:GuardianRelatorioEmMemoria = $jsonObject
$script:GuardianJsonDestino = $jsonFilePath
# Fecha a tela gráfica do Guardian ao terminar o script, se estiver aberta
# v2 console: nao ha controle WPF nesta etapa.

# Exibe a UI amigável enquanto o script continua rodando
# v2 laboratorio: sem interface de encerramento.

# Pausa breve para garantir que a UI feche antes do término do script
Start-Sleep -Milliseconds 500

#region Envio do Log para Servidor de Arquivos
#if ($FileServer -and $FileServer.Trim() -ne '') {
#    Write-GuardianStatus ("Enviando log para o servidor: {0}" -f $FileServer) 'INFO'
#    Send-LogToServer -Server $FileServer
#} else {
#    Write-GuardianStatus "Nenhum servidor informado: pulando envio do log." 'INFO'
#}
#endregion

} catch {
    $script:GuardianFalhaGeral = $true
    Write-GuardianStatus ("FALHA GERAL (capturada): {0}" -f $_.ToString()) 'ERROR'
} finally {

    $argJsonPath = "C:\Guardian\guardian_arg.json"
    if (Test-Path $argJsonPath) {
        try { Remove-Item $argJsonPath -Force -ErrorAction SilentlyContinue > $null 2>&1 } catch {}
    }


    if ($script:GuardianRelatorioEmMemoria) {
        try {
            # Telemetria pertence exclusivamente ao motor e entra no relatorio em memoria.
            # Um erro de coleta bloqueia o envio para evitar dados incompletos na API.
            $telemetryPath = Join-Path $funcDir 'Get-HardwareTelemetry.ps1'
            if (-not (Test-Path -LiteralPath $telemetryPath -PathType Leaf)) {
                throw 'Modulo Get-HardwareTelemetry.ps1 ausente.'
            }
            $telemetryOutput = @(& $telemetryPath -ErrorAction Stop)
            $telemetryObjects = @($telemetryOutput | Where-Object {
                $null -ne $_ -and $_.PSObject.Properties.Name -contains 'schema_version'
            })
            if ($telemetryObjects.Count -ne 1) {
                throw ("Telemetria: esperado um objeto, obtidos {0}." -f $telemetryObjects.Count)
            }
            $telemetryData = $telemetryObjects[0]
            if ($telemetryData.schema_version -ne 1 -or
                $telemetryData.status -notin @('ok', 'parcial') -or
                [string]$telemetryData.computador -ine [string]$script:GuardianRelatorioEmMemoria.NomeComputador) {
                throw 'Telemetria invalida ou identificador de computador divergente.'
            }
            $script:GuardianRelatorioEmMemoria | Add-Member -NotePropertyName 'telemetria' -NotePropertyValue $telemetryData -Force

            & "C:\Guardian\Functions\Optimize-JsonReport.ps1" `
                -Relatorio $script:GuardianRelatorioEmMemoria `
                -JsonDestino $script:GuardianJsonDestino `
                -NaoEnviarApi:([bool]$Simulado) -ErrorAction Stop
        } catch {
            $global:GuardianEnvioApiStatus = 'Nao enviado (relatorio invalido)'
            Write-Host ("  ERRO  Falha na consolidacao do JSON: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    } else {
        Write-Host '  ERRO  Relatorio em memoria indisponivel; nenhum JSON enviado.' -ForegroundColor Red
    }

    # =========================================================================
    # Gravar guardian.json com data da execucao bem-sucedida
    # =========================================================================
    try {
        $guardianJsonPath = "C:\Guardian\guardian.json"
        $guardianResult = @{
            ultima_execucao = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        if (-not $Dev -and (Test-Path -LiteralPath $script:GuardianJsonDestino)) { $guardianResult | ConvertTo-Json | Set-Content -Path $guardianJsonPath -Encoding UTF8 -Force }
    } catch {}


# GUARDA DE SEGURANÇA DOS AGENDAMENTOS — UI 10
# Validação NÃO DESTRUTIVA: nenhuma tarefa é registrada, renomeada ou removida.
# A normalização automática será retomada após auditoria dos XMLs do laboratório.
$script:GuardianTasksPadronizadas = $false
$script:GuardianTasksVerificadas = $false
try {
    $tasks = @(Get-ScheduledTask -TaskPath '\Guardian\' -ErrorAction Stop)
    $principal = @($tasks | Where-Object {
        $_.TaskName -match '^1\.\s+Guardian(?:\s|$)' -and
        $_.TaskName -notmatch '(?i)System|Ghost'
    })
    $system = @($tasks | Where-Object { $_.TaskName -eq '2. Guardian System' })
    $ghost = @($tasks | Where-Object { $_.TaskName -eq '3. Guardian Ghost' })
    $missing = @()
    if ($principal.Count -ne 1) { $missing += 'Guardian principal' }
    if ($system.Count -ne 1) { $missing += 'Guardian System' }
    if ($ghost.Count -ne 1) { $missing += 'Guardian Ghost' }
    if ($missing.Count -eq 0) {
        $script:GuardianTasksVerificadas = $true
    } else {
        Write-GuardianConsoleEvent -Text ('Agendamentos incompletos: ' + ($missing -join ', ')) -Kind WARN
    }
}
catch {
    Write-GuardianConsoleEvent -Text ('Não foi possível consultar os agendamentos: ' + $_.Exception.Message) -Kind WARN
}

    if ($script:GuardianTasksVerificadas) { Write-GuardianConsoleEvent 'Agendamentos verificados' }
    if ($scriptStart -and $scriptStart.IsRunning) { $scriptStart.Stop() }
    $qtdEtapas = @($jsonResults).Count
    $qtdFases = @($script:GuardianSelectedPhases).Count
    $qtdAvisos = @($jsonResults | Where-Object { $_.Status -ne 'OK' }).Count
    $wingetInconsistente = @($jsonResults | Where-Object {
        $_.Phase -match 'Winget' -and $_.Mensagem -isnot [string] -and
        $_.Mensagem -and $_.Mensagem.AtualizacaoBemSucedida -eq $false
    }).Count -gt 0
    $integridadeSuspeita = @($jsonResults | Where-Object {
        $_.Phase -match 'Registro e dos arquivos' -and $_.Mensagem -isnot [string] -and
        $_.Mensagem -and ($_.Mensagem.SfcCorrompido -eq $true -or $_.Mensagem.DismCorrompido -eq $true)
    }).Count -gt 0
    $resumoJsonOk = $false
    if ($script:GuardianJsonDestino) { $resumoJsonOk = Test-Path -LiteralPath $script:GuardianJsonDestino -PathType Leaf }
    $pendencias = @()
    if ($wingetInconsistente) { $pendencias += 'Winget: resultado interno exige verificacao' }
    if ($integridadeSuspeita) { $pendencias += 'Integridade: divergencia nos dados da fase 02' }
    if (-not $script:GuardianTasksVerificadas) { $pendencias += 'Agendamentos: validação incompleta' }
    foreach ($p in $pendencias) { Write-GuardianConsoleEvent $p WARN }
    $statusOk = (-not $script:GuardianFalhaGeral -and $resumoJsonOk)
    $statusTexto = if (-not $statusOk) { 'EXECUCAO COM FALHA' } elseif ($qtdAvisos -gt 0 -or $pendencias.Count -gt 0) { 'CONCLUIDO COM RESSALVAS' } else { 'CONCLUIDO' }
    Write-Host ''
    Write-Host ('  ' + ('─' * 51)) -ForegroundColor DarkGray
    Write-Host ('  {0}' -f $statusTexto) -ForegroundColor $(if ($statusOk -and $pendencias.Count -eq 0 -and $qtdAvisos -eq 0) { 'White' } else { 'Yellow' })
    Write-Host ('  Fases         {0} / {0}' -f $qtdFases) -ForegroundColor White
    Write-Host ('  Etapas        {0}' -f $qtdEtapas) -ForegroundColor White
    Write-Host ('  Tempo         {0}' -f (Format-Elapsed $scriptStart.Elapsed)) -ForegroundColor White
    Write-Host ('  Relatorio     {0}' -f $(if ($resumoJsonOk) { 'JSON gerado' } else { 'Indisponivel' })) -ForegroundColor White
    Write-Host ('  API           {0}' -f $global:GuardianEnvioApiStatus) -ForegroundColor White
    Write-Host ('  ' + ('─' * 51)) -ForegroundColor DarkGray
    # A nota exibida na WPF e lida APENAS do JSON definitivo ja consolidado.
    # Nenhum arquivo temporario nem alteracao de esquema/API.
    $uiHealth = @{}
    $finalReport = $null
    if ($resumoJsonOk) {
        try {
            $finalReport = Get-Content -LiteralPath $script:GuardianJsonDestino -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($finalReport.SaudeGeral -and $null -ne $finalReport.SaudeGeral.Nota) {
                $uiHealth = @{
                    score = [int][Math]::Round([double]$finalReport.SaudeGeral.Nota)
                    classification = [string]$finalReport.SaudeGeral.Classificacao
                }
            }
            # Notas parciais ja consolidadas no JSON final: somente para exibicao na LiveUI.
            # Nenhum recalculo, persistencia ou alteracao na API.
            if ($null -ne $finalReport.SaudeGeral.Detalhes) {
                $uiHealth.breakdown = $finalReport.SaudeGeral.Detalhes
            }
            # Justificativas APENAS para a LiveUI, sem recalcular notas ou alterar o JSON/API.
            # Derivadas dos mesmos campos utilizados pelo Optimize-JsonReport.ps1.
            try {
                $scoreReasons = @{}
                $scoreDetails = $finalReport.SaudeGeral.Detalhes
                $scorePhases = @($finalReport.Fases)
                $inventory = @($scorePhases | Where-Object { $_.Phase -match 'Coleta do Inventário' } | Select-Object -First 1)
                $inventoryData = if ($inventory.Count -gt 0) { $inventory[0].Mensagem } else { $null }

                # Atualizacoes: explicacao ao cliente sem expor falhas pontuais do Winget.
                # Preserva o resultado real de Windows Update e informa a gestao automatica da Loja.
                $winUpdate = @($scorePhases | Where-Object { $_.Phase -match 'Atualização do Windows' } | Select-Object -First 1)
                if ($winUpdate.Count -eq 0) {
                    $windowsUpdateReason = 'Windows Update: sem execução registrada.'
                } elseif ($winUpdate[0].Mensagem -isnot [string] -and
                          $winUpdate[0].Mensagem.AtualizacaoBemSucedida -eq $true) {
                    $windowsUpdateReason = 'Windows Update: atualização concluída com sucesso.'
                } else {
                    $windowsUpdateReason = 'Windows Update: conclusão da atualização não confirmada.'
                }
                $scoreReasons.Atualizacoes = $windowsUpdateReason + ' Aplicativos da Microsoft Store: atualizações gerenciadas automaticamente pelo Windows.'

                # Particoes: identificar a unidade responsável pelo desconto.
                $parts = @($inventoryData.Particoes | Where-Object { $null -ne $_.UsadoPct } |
                    Sort-Object -Property @{ Expression = { [double]$_.UsadoPct }; Descending = $true })
                if ($parts.Count -gt 0) {
                    $worst = $parts[0]
                    $scoreReasons.Particoes = ('Unidade {0}: {1:N1}% do espaço utilizado.' -f [string]$worst.Letra, [double]$worst.UsadoPct)
                } else { $scoreReasons.Particoes = 'Dados de ocupação das partições não disponíveis.' }

                # Atualmente essas duas notas são fixas no cálculo. Não atribuir análises inexistentes.
                $scoreReasons.IntegridadeSistema = 'Integridade acompanhada por procedimentos automáticos do Guardian Ghost.'
                # A descricao confirma somente etapas de limpeza registradas como concluidas.
                $cleanPhases = @($scorePhases | Where-Object { $_.Phase -match 'Limpeza das pastas temporárias|Limpeza dos arquivos temporários dos componentes do Windows' })
                $cleanOK = @($cleanPhases | Where-Object { $_.Status -eq 'OK' -and (
                    ($_.Mensagem -is [string] -and $_.Mensagem -match 'concluíd|limp|removid') -or
                    ($_.Mensagem -isnot [string] -and ($_.Mensagem.LimpezaBemSucedida -eq $true))
                ) })
                if ($cleanOK.Count -gt 0) {
                    $scoreReasons.Limpezas = 'Arquivos temporários e resíduos do sistema removidos durante a manutenção preventiva.'
                } elseif ($cleanPhases.Count -gt 0) {
                    $scoreReasons.Limpezas = 'Resultado das rotinas de limpeza não confirmado nesta vistoria.'
                } else {
                    $scoreReasons.Limpezas = 'Rotinas de limpeza sem execução registrada nesta vistoria.'
                }

                # Backup Macrium: somente motivos verificáveis a partir do inventário.
                $backupData = $inventoryData.BackupMacrium
                if ($null -eq $backupData) {
                    $scoreReasons.Backup = 'Informações do backup não disponíveis no inventário.'
                } elseif ($backupData.ExisteParticaoD -ne $true) {
                    $scoreReasons.Backup = 'Partição D: exigida pela regra de backup não identificada.'
                } elseif ($backupData.ExistePastaRescue -ne $true) {
                    $scoreReasons.Backup = 'Pasta Rescue não identificada na partição D:.'
                } elseif ($backupData.ExistemImagens -ne $true) {
                    $scoreReasons.Backup = 'Nenhuma imagem de backup Macrium foi identificada.'
                } elseif ($backupData.DataImagem1) {
                    $backupDays = ([datetime]::Now - [datetime]$backupData.DataImagem1).Days
                    $scoreReasons.Backup = ('Imagem de backup mais recente: {0} dia(s).' -f [Math]::Max(0,$backupDays))
                } else { $scoreReasons.Backup = 'Data da imagem de backup não disponível.' }

                # Rede: a justificativa visual deve descrever o adaptador realmente conectado.
                # Nao modifica o criterio nem a pontuacao calculada pelo Optimize-JsonReport.
                $nets = @($inventoryData.Redes | Where-Object { $null -ne $_ })
                $activeNets = @($nets | Where-Object { ([string]$_.Status).Trim() -match '^(Up|Connected|Conectado)$' })
                $net = $activeNets | Where-Object { ([string]$_.Adaptador) -match '^(Wi-Fi|WiFi|WLAN|Wireless|Rede sem fio)' } | Select-Object -First 1
                if (-not $net) { $net = $activeNets | Where-Object { ([string]$_.Adaptador) -match '^Ethernet' } | Select-Object -First 1 }
                if (-not $net) { $net = $activeNets | Select-Object -First 1 }
                if ($net) {
                    $networkName = [string]$net.Adaptador
                    $networkType = if ($networkName -match '^(Wi-Fi|WiFi|WLAN|Wireless|Rede sem fio)') { 'Rede sem fio' } else { $networkName }
                    $networkSpeed = if ($net.Velocidade -and ([string]$net.Velocidade).Trim() -notmatch '^(0(\s*\w+)?|0\s*[kmg]?bps)$') { [string]$net.Velocidade } else { 'não informada' }
                    $scoreReasons.Rede = ('{0} conectada; velocidade {1}.' -f $networkType, $networkSpeed)
                } elseif ($nets.Count -gt 0) {
                    $scoreReasons.Rede = 'Nenhum adaptador de rede ativo identificado nesta vistoria.'
                } else { $scoreReasons.Rede = 'Nenhum adaptador de rede identificado no inventário.' }

                # Segurança: não confundir ausência de confirmação com malware detectado.
                $defenderPhase = @($scorePhases | Where-Object { $_.Phase -match 'Windows Defender' } | Select-Object -First 1)
                if ($defenderPhase.Count -eq 0) {
                    $scoreReasons.Seguranca = 'Varredura do Windows Defender sem execução registrada.'
                } elseif ($defenderPhase[0].Mensagem -isnot [string] -and
                    $defenderPhase[0].Mensagem.ScanBemSucedido -eq $true) {
                    $scoreReasons.Seguranca = 'Varredura do Windows Defender concluída com sucesso.'
                } else {
                    $scoreReasons.Seguranca = 'Conclusão da varredura do Windows Defender não confirmada.'
                }

                $uiHealth.scoreReasons = $scoreReasons
            } catch { } # Justificativas opcionais nunca bloqueiam a conclusao do Guardian.
        } catch { } # A ausencia da nota nao muda o resultado da manutencao.
    }
    # Dados complementares são enviados exclusivamente à WPF a partir do JSON consolidado.
    $uiHealth.duration = Format-Elapsed $scriptStart.Elapsed
    # Resultado de integracao ja definido pelo Optimize-JsonReport.ps1.
    # Informacao apenas visual; preserva o JSON, a API e a nota oficial.
    $apiStatusText = [string]$global:GuardianEnvioApiStatus
    $uiHealth.apiStatus = if ($apiStatusText -match '(?i)^(Falhou|Falha|N[aã]o enviado)') { 'pending' } else { 'other' }
    # Apenas a LiveUI recebe os IDs ignorados; nao altera o JSON final nem a API.
    $uiHealth.skippedPhases = @($PulaFases)
    if ($resumoJsonOk -and $null -ne $finalReport -and $finalReport.PSObject.Properties.Name -contains 'telemetria' -and $null -ne $finalReport.telemetria -and $null -ne $finalReport.telemetria.eventos_windows) {
        $ev = $finalReport.telemetria.eventos_windows
        function Convert-GuardianEventTotal {
            param($Value)
            if ($null -eq $Value -or $null -eq $Value.total) { return 'Não disponível' }
            return [string]$Value.total
        }
        $uiHealth.events = @{
            whea = Convert-GuardianEventTotal $ev.whea
            bsod = Convert-GuardianEventTotal $ev.telas_azuis
            shutdown = Convert-GuardianEventTotal $ev.desligamentos_inesperados
            disk = Convert-GuardianEventTotal $ev.erros_disco
        }
    }
    Send-GuardianLiveEvent -Type 'complete' -Label $statusTexto -Percent 100 -Status $(if (-not $statusOk) { 'error' } elseif ($qtdAvisos -gt 0 -or $pendencias.Count -gt 0) { 'warning' } else { 'ok' }) -Data $uiHealth
    Disable-QuickEditProtection
    Disable-ConsoleAppearance
}
