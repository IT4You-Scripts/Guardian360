<#
.SYNOPSIS
    Framework de Manutenção Preventiva, Atualização e Otimização para Windows 10 e 11.

.DESCRIPTION
    Este script orquestra um conjunto de funções organizadas em etapas cronológicas para:
    - Diagnóstico do sistema
    - Correção de integridade
    - Otimizações estruturais
    - Limpeza de arquivos temporários
    - Atualizações controladas
    - Pós-atualização
    - Otimização de armazenamento
    - Segurança e validação de backups
    - Gestão de logs

.NOTES
    Funcionalidades principais:
    - Validação do ambiente (Administrador, Windows, versão mínima do PowerShell)
    - Instalação automática do PowerShell 7+ se necessário (silenciosa; sem prompts)
    - Reexecução transparente no PowerShell 7+ se disponível
    - Tratamento de erros por etapa com registro em log (sem “erros vermelhos” na tela)
    - Execução autônoma (sem interação do usuário), ideal para Agendador de Tarefas
    - Compatível com o sistema operacional Microsoft Windows

.AUTHOR
    IT4You Ltda
.VERSION
    1.5
.LASTUPDATED
    11/01/2026
#>

[CmdletBinding()]
param(
  [int[]]$ExecutaFases,  # Se não for informado, executa todas as fases
  [int[]]$PulaFases,     # Se não for informado, nenhuma fase será pulada
  [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$LogLevel = 'INFO',
  [switch]$Simulado      # Modo ensaio: não executa ações destrutivas
)

# Preferências e ambiente
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Caminhos
$root    = Split-Path -Parent $PSCommandPath
$funcDir = Join-Path $root 'Functions'

# --- Início: Ajuste Mínimo de Pasta/Arquivo de Log ---
$baseLogDir  = Join-Path $root 'Logs'
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$year        = Get-Date -Format 'yyyy'
$monthNumber = Get-Date -Format 'MM'
$monthName   = (Get-Culture).DateTimeFormat.GetMonthName([int]$monthNumber)
$monthFolder = ("{0}. {1}" -f $monthNumber, (Get-Culture).TextInfo.ToTitleCase($monthName.ToLower()))
$logDir      = Join-Path (Join-Path $baseLogDir $year) $monthFolder
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$computer    = $env:COMPUTERNAME.ToUpper()
$logFile     = Join-Path $logDir ("{0}_{1}.log" -f $computer, $stamp)
# --- Fim: Ajuste Mínimo de Pasta/Arquivo de Log ---

# TLS forte (sem prompts)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# Resultados agregados
$global:Results = New-Object System.Collections.Generic.List[object]

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
  'Update-WingetApps'        = 'Atualização dos programas instalados via Winget'
  'Update-ChocoApps'         = 'Atualização dos programas instalados via Chocolatey'
  'Update-WindowsSystem'     = 'Atualização do Windows'
  'Remove-OldUpdateFiles'    = 'Limpeza dos arquivos temporários dos componentes do Windows'
  'Optimize-SSD'             = 'Otimização de todos os SSDs disponíveis'
  'Optimize-HDD'             = 'Desfragmentação de todos os discos físicos disponíveis'
  'Scan-AntiMalware'         = 'Varredura contra malwares com Windows Defender'
  'Confirm-MacriumBackup'    = 'Validação dos arquivos de backup do Macrium Reflect'
  'Send-LogToServer'         = 'Verificação da existência de Servidor de Arquivos na rede local'
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
  $Reset  = $pss.Value.Reset
} else {
  $Cyan=''; $Green=''; $Yellow=''; $Gray=''; $Reset=''
}

function Write-Report {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($Text)) {
    "" | Out-File -FilePath $logFile -Append -Encoding UTF8
    return
  }
  $Text | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Write-Log {
  param([string]$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level='INFO')
  $levelsPriority = @{ 'ERROR'=3; 'WARN'=2; 'INFO'=1; 'DEBUG'=0 }
  if ($levelsPriority[$Level] -lt $levelsPriority[$LogLevel]) { return }
  $line = "[{0:u}] [{1}] {2}" -f (Get-Date), $Level, $Message

  # Arquivo: filtrar para manter só o que deve ir ao log final
  $shouldWriteRawToFile = $false
  $rawToWrite = $null

  if ($global:ConciseLog) {
    # Inventário: gravar apenas o conteúdo textual (sem prefixos/rotulagens)
    if ($global:CurrentStepTitle -eq 'Get-SystemInventory') {
      if ($Message -match '^Iniciando:' -or $Message -match '^Informações do Inventário' -or $Message -eq '') {
        $shouldWriteRawToFile = $false
      } else {
        $shouldWriteRawToFile = $true
        $rawToWrite = $Message
      }
    }


  } else {
    # Se não conciso, gravaria tudo no arquivo
    $shouldWriteRawToFile = $false
  }

  if ($shouldWriteRawToFile) {
    Write-Report -Text $rawToWrite
  } elseif (-not $global:ConciseLog) {
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
  }

  # Console amigável (sem “erros vermelhos” do PowerShell)
  switch ($Level) {
    'ERROR' { Write-Host ("{0}[ALERTA]{1} {2}" -f $Yellow, $Reset, $Message) }
    'WARN'  { Write-Host ("{0}[AVISO]{1}  {2}" -f $Yellow, $Reset, $Message) }
    'DEBUG' { Write-Host ("{0}[DEBUG]{1}  {2}" -f $Gray,   $Reset, $Message) }
    default { Write-Host (""  -f $Gray,   $Reset, $Message) }
  }
}

function Show-Header {
  param([string]$Text)
  $bar = '─' * ($Text.Length + 2)
  # Write-Host ""
  Write-Host ("{0}┌{1}┐{2}" -f $Cyan, $bar, $Reset)
  Write-Host ("{0}│ {1} │{2}" -f $Cyan, $Text, $Reset)
  Write-Host ("{0}└{1}┘{2}" -f $Cyan, $bar, $Reset)
}

function Show-Phase {
  param([int]$Id,[string]$Title)
  Write-Host ""
  Write-Host ""
  Write-Host ("{0}► Fase {1}:{2} {3}" -f $Cyan, $Id, $Reset, $Title)
}

function Show-StepStart {
  param([string]$Name)
  Write-Host ("  {0}•{1} Iniciando: {2} ..." -f $Gray, $Reset, $Name)
}
function Show-StepEnd {
  param([string]$Name,[TimeSpan]$Elapsed,[bool]$Ok)
  if ($Ok) {
    Write-Host ("  {0}✓{1} {2} concluída com sucesso em {3}" -f $Green, $Reset, $Name, (Format-Elapsed $Elapsed))
  } else {
    Write-Host ("  {0}!{1} {2} finalizada com alertas (veja o log). Tempo: {3}" -f $Yellow, $Reset, $Name, (Format-Elapsed $Elapsed))
  }
}

function Test-IsAdmin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-AdminOrExit {
  if (-not (Test-IsAdmin)) {
    Show-Header -Text 'Permissão insuficiente'
    Write-Log "A execução requer privilégios administrativos. Agende como Admin/SYSTEM. Encerrando." 'ERROR'
    exit 1
  }
}

function Initialize-Pwsh7 {
  if ($PSVersionTable.PSVersion.Major -ge 7) { return }
  Write-Log 'PowerShell 7+ não detectado. Tentando instalação silenciosa...' 'INFO'
  $installed = $false
  try {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements --silent | Out-Null
      $installed = $true
    }
  } catch { Write-Log ("Falha com winget: {0}" -f $_.Exception.Message) 'WARN' }

  if (-not $installed) {
    try {
      $msi = Join-Path $env:TEMP 'PowerShell7.msi'
      $url = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.1-win-x64.msi'
      Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
      Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
      $installed = $true
    } catch { Write-Log ("Falha no download/instalação do MSI: {0}" -f $_.Exception.Message) 'WARN' }
  }

  if ($installed) {
    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if ($null -ne $pwsh) {
      Write-Log 'Reiniciando no PowerShell 7 (silencioso)...' 'INFO'
      Start-Process $pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -WindowStyle Hidden
      exit 0
    }
  }

  Write-Log 'PS7 não disponível. Continuando no host atual sem interromper.' 'WARN'
}

function Start-Logging {

    $dataHoraFormatada = Get-Date -Format "dd/MM/yyyy 'às' HH'h' mm'min'"

    Write-Log    ("Guardian 360 ({0})" -f $dataHoraFormatada) 'INFO'
    Write-Log "____________________________________________________________________________________________________________________________________"
    Write-Report ("Guardian 360 ({0})" -f $dataHoraFormatada)
    Write-Report "____________________________________________________________________________________________________________________________________"
}

function Stop-Logging {
  Write-Log 'Fim da execução Guardian360' 'INFO'
}

function Get-RebootPending {
  try {
    $keys = @(
      'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
      'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
      'HKLM:SYSTEM\CurrentControlSet\Control\Session Manager'
    )
    foreach($k in $keys){ if (Test-Path $k) { return $true } }
    $val = (Get-ItemProperty -Path 'HKLM:SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue)
    return [bool]$val
  } catch { return $false }
}

function Test-Internet { Test-Connection -ComputerName 1.1.1.1 -Quiet -Count 1 -ErrorAction SilentlyContinue }

function Get-PhysicalDisksByType {
  $list = @()
  try {
    $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($null -ne $disks -and @($disks).Count -gt 0) {
      $list = @($disks) | Select-Object FriendlyName, MediaType
    } else {
      $fallback = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
      if ($null -ne $fallback -and @($fallback).Count -gt 0) {
        $list = @($fallback) | ForEach-Object {
          [pscustomobject]@{
            FriendlyName = $_.Model
            MediaType    = (if ($_.Model -match 'SSD') { 'SSD' } else { 'HDD' })
          }
        }
      } else {
        $list = @() # nenhum disco detectado
      }
    }
  } catch {
    $list = @()
  }
  return ,$list
}

function Format-Elapsed {
  param([TimeSpan]$Elapsed)
  $min = [int][Math]::Floor($Elapsed.TotalMinutes)
  $sec = $Elapsed.Seconds
  return ('{0:00} min {1:00} seg' -f $min, $sec)
}

#region Bloco de Proteção QuickEdit ---
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

function Invoke-QuickEditLog {
    param([string]$Message, [string]$Level = 'INFO')
    try { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level } } catch {}
}

function Get-ConsoleInputMode {
    $handle = [Kernel32]::GetStdHandle(-10)  # STD_INPUT_HANDLE
    $mode = 0
    [Kernel32]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    return $mode
}

function Set-ConsoleInputMode {
    param([uint32]$Mode)
    $handle = [Kernel32]::GetStdHandle(-10)  # STD_INPUT_HANDLE
    [Kernel32]::SetConsoleMode($handle, $Mode) | Out-Null
}

# Constantes para modos de console
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

# Registrar evento para restaurar ao sair
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Disable-QuickEditProtection }
#endregion

#region Bloco de Aparência para o Console (Maximizar + Fundo Preto) ---
# Tipo Win32 para maximizar
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

# Estado interno
$script:_Console_OrigBgColor = $null

function Invoke-ConsoleLog {
  param([string]$Message,[string]$Level='DEBUG')
  try { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level } } catch {}
}

function Test-HasRawUI {
  try { return ($null -ne $Host -and $null -ne $Host.UI -and $null -ne $Host.UI.RawUI) } catch { return $false }
}

function Expand-ConsoleWindow {
  try {
    $hWnd = [Win32.ConsoleWindow]::GetConsoleWindow()
    if ($hWnd -ne [IntPtr]::Zero) {
      [void][Win32.ConsoleWindow]::ShowWindow($hWnd, 3) # SW_MAXIMIZE
    }
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
  } catch {
    Invoke-ConsoleLog ("Falha ao maximizar console: {0}" -f $_.Exception.Message) 'WARN'
  }
}

function Enable-ConsoleAppearance {
  [CmdletBinding()]
  param([switch]$ForceMaximize = $true)

  $hostName = ''
  try { $hostName = $Host.Name } catch {}
  $isDesignHost = ($hostName -match 'ISE' -or $hostName -match 'Visual Studio Code')

  if (Test-HasRawUI) {
    try {
      if ($null -eq $script:_Console_OrigBgColor) {
        $script:_Console_OrigBgColor = $Host.UI.RawUI.BackgroundColor
      }
      $Host.UI.RawUI.BackgroundColor = 'Black'
      #Clear-Host
      Invoke-ConsoleLog 'Aparência: fundo preto aplicado.'
    } catch {
      Invoke-ConsoleLog ("Falha ao aplicar fundo preto: {0}" -f $_.Exception.Message) 'WARN'
    }
  }

  if (-not $isDesignHost) {
    if ($ForceMaximize) { Expand-ConsoleWindow }
  } else {
    Invoke-ConsoleLog "Maximização ignorada em host ($hostName)."
  }
}

function Disable-ConsoleAppearance {
  [CmdletBinding()]
  param()
  if (Test-HasRawUI) {
    try {
      if ($null -ne $script:_Console_OrigBgColor) {
        $Host.UI.RawUI.BackgroundColor = $script:_Console_OrigBgColor
        #Clear-Host
        Invoke-ConsoleLog 'Aparência: fundo original restaurado.'
      }
    } catch {
      Invoke-ConsoleLog ("Falha ao restaurar aparência: {0}" -f $_.Exception.Message) 'WARN'
    } finally {
      $script:_Console_OrigBgColor = $null
    }
  }
}

# Restauração em saídas inesperadas
if (-not (Get-Variable -Name ConsoleAppearance_AtExitHandler -Scope Script -ErrorAction SilentlyContinue)) {
  $script:ConsoleAppearance_AtExitHandler = { try { Disable-ConsoleAppearance } catch {} }
  try { Register-EngineEvent PowerShell.Exiting -Action $script:ConsoleAppearance_AtExitHandler | Out-Null } catch {}
}
#endregion

function Invoke-GuardianStep {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][scriptblock]$Action
  )
  $label = Get-StepLabel $Title
  Write-Log ("Iniciando: {0}" -f $Title) 'INFO'
  Show-StepStart -Name $label
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $ok = $true
  $global:CurrentStepTitle = $Title
  try {
    if ($Simulado) {
      Write-Log ("SIMULADO: ação não executada para '{0}'." -f $Title) 'DEBUG'
    } else {
      & $Action
    }
  } catch {
    $ok = $false
    Write-Log ("Etapa '{0}' registrou erro: {1}" -f $Title, $_.ToString()) 'ERROR'
  } finally {
    $global:CurrentStepTitle = $null
  }
  $sw.Stop()
  $global:Results.Add([pscustomobject]@{ Etapa=$label; EtapaTecnica=$Title; Sucesso=$ok; Tempo=$sw.Elapsed })
  Show-StepEnd -Name $label -Elapsed $sw.Elapsed -Ok:$ok
}

# 1) Pré-requisitos (sem prompts)
Test-AdminOrExit
Initialize-Pwsh7
Enable-QuickEditProtection
Enable-ConsoleAppearance
Start-Logging
Clear-Host
Show-Header -Text 'Guardian 360 — Manutenção e Otimização'

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
    'Update-WingetApps.ps1',
    'Update-ChocoApps.ps1',
    'Update-WindowsSystem.ps1',
    'Remove-OldUpdateFiles.ps1',
    'Optimize-SSD.ps1',
    'Optimize-HDD.ps1',
    'Scan-AntiMalware.ps1',
    'Confirm-MacriumBackup.ps1',
    'Send-LogToServer.ps1'
  )
  foreach ($ff in $functionFiles) {
    $path = Join-Path $funcDir $ff
    if (-not (Test-Path $path)) {
      Write-Log ("Arquivo de função não encontrado: {0}" -f $path) 'ERROR'
      continue
    }
    try { . $path } catch { Write-Log ("Falha ao carregar {0}: {1}" -f $ff, $_.ToString()) 'ERROR' }
  }

  # 3) Detectores de cenário
  $hasInet = Test-Internet
  $disks   = Get-PhysicalDisksByType
  $hasSSD = @($disks | Where-Object { $_.MediaType -match 'SSD' }).Count -gt 0
  $hasHDD = @($disks | Where-Object { $_.MediaType -match 'HDD|Unspecified' }).Count -gt 0

  # 4) Fases e passos
  $Phases = @(
    @{ Id=1; Title='Inventário de Hardware e Software'; Steps=@(
        @{ Name='Get-SystemInventory';   Action={ Get-SystemInventory } }
      )},
    @{ Id=2; Title='Integridade do Sistema'; Steps=@(
        @{ Name='Repair-SystemIntegrity'; Action={ Repair-SystemIntegrity } }
      )},
    @{ Id=3; Title='Otimizações Estruturais'; Steps=@(
        @{ Name='Optimize-PowerSettings';    Action={ Optimize-PowerSettings } },
        @{ Name='Optimize-NetworkSettings';  Action={ Optimize-NetworkSettings } }
      )},
    @{ Id=4; Title='Limpeza de arquivos temporários'; Steps=@(
        @{ Name='Clear-BrowserCache';        Action={ Clear-BrowserCache } },
        @{ Name='Clear-AllRecycleBins';      Action={ Clear-AllRecycleBins } },
        @{ Name='Clear-TempFiles';           Action={ Clear-TempFiles } },
        @{ Name='Clear-WindowsUpdateCache';  Action={ Clear-WindowsUpdateCache } },
        @{ Name='Clear-RecentFilesHistory';  Action={ Clear-RecentFilesHistory } }
      )},
    @{ Id=5; Title='Atualizações Controladas'; Steps=@(
        #@{ Name='Block-AppUpdates';     Action={ Block-AppUpdates } },
        @{ Name='Update-WingetApps';    Action={ if($hasInet){ Update-WingetApps } else { Write-Log 'Sem internet: pulando Update-WingetApps' 'WARN' } } },
        @{ Name='Update-ChocoApps';     Action={ if($hasInet){ Update-ChocoApps } else { Write-Log 'Sem internet: pulando Update-ChocoApps' 'WARN' } } },
        @{ Name='Update-WindowsSystem'; Action={ if($hasInet){ Update-WindowsSystem } else { Write-Log 'Sem internet: pulando Update-WindowsSystem' 'WARN' } } }
      )},
    @{ Id=6; Title='Pós-atualização / Componentes'; Steps=@(
        @{ Name='Remove-OldUpdateFiles'; Action={ Remove-OldUpdateFiles } }
      )},
    @{ Id=7; Title='Otimização de Armazenamento'; Steps=@(
        @{ Name='Optimize-SSD'; Action={ if($hasSSD){ Optimize-SSD } else { Write-Log 'Nenhum SSD detectado: pulando Optimize-SSD' 'INFO' } } },
        @{ Name='Optimize-HDD'; Action={ if($hasHDD){ Optimize-HDD } else { Write-Log 'Nenhum HDD detectado: pulando Optimize-HDD' 'INFO' } } }
      )},
    @{ Id=8; Title='Segurança'; Steps=@(
        @{ Name='Scan-AntiMalware';       Action={ Scan-AntiMalware } }        
      )},
    @{ Id=9; Title='Gestão'; Steps=@(
        @{ Name='Send-LogToServer'; Action={ Send-LogToServer } }
      )}
  )

  # 5) Execução por fase
  foreach ($phase in $Phases) {
    $id = [int]$phase.Id
    if ($ExecutaFases -and ($ExecutaFases -notcontains $id)) { continue }
    if ($PulaFases -and ($PulaFases -contains $id)) { continue }

    Write-Host ""
    # Write-Host "____________________________________________________________________________________________________________________________________"
    Show-Phase -Id $phase.Id -Title $phase.Title
    Write-Log ("=== Fase {0}: {1} ===" -f $phase.Id, $phase.Title) 'INFO'

    foreach ($step in $phase.Steps) {
      Invoke-GuardianStep -Title $step.Name -Action $step.Action
    }

    if ($id -eq 5 -and (Get-RebootPending)) {
      Write-Log 'Reinicialização pendente detectada após Atualizações.' 'WARN'
      Write-Host ("{0}› Uma reinicialização está pendente. Ela pode ser realizada fora desta janela de manutenção.{1}" -f $Yellow, $Reset)
    }
  }

  # 6) Resumo final
  Write-Host ""
  Clear-Host   # Descomentar esta linha na versão final do Script
  Show-Header -Text 'Resumo da Manutenção Automatizada'
  Write-Host ""

  $maxLabel = 0
  foreach ($r in $global:Results) {
    if ($r.Etapa.Length -gt $maxLabel) { $maxLabel = $r.Etapa.Length }
  }

  Write-Report ""
  Write-Report "Resumo da Manutenção Automatizada"
  Write-Report ""
  
  foreach ($r in $global:Results) {
    $statusPlain = if ($r.Sucesso) { 'OK' } else { 'ALERTA' }
    $labelPadded = $r.Etapa.PadRight($maxLabel)
    $elapsedTxt = (Format-Elapsed $r.Tempo)

    $statusConsole = if ($r.Sucesso) { "{0}OK{1}" -f $Green, $Reset } else { "{0}ALERTA{1}" -f $Yellow, $Reset }
    Write-Host ("- {0}  -> {1} (Tempo: {2})" -f $labelPadded, $statusConsole, $elapsedTxt)

    Write-Report ("- {0}  -> {1} (Tempo: {2})" -f $labelPadded, $statusPlain, $elapsedTxt)
  }


  Confirm-MacriumBackup

  Write-Host ""
  Write-Host ("{0}Arquivo de log:{1} {2}" -f $Gray, $Reset, $logFile)
  Write-Host ""
  
  Write-Report ""
  Write-Report ("Arquivo de log: {0}" -f $logFile)
  
} catch {
  Write-Log ("FALHA GERAL (capturada): {0}" -f $_.ToString()) 'ERROR'
} finally {
  Disable-QuickEditProtection
  Disable-ConsoleAppearance
  Stop-Logging
}