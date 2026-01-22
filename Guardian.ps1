#Requires -Version 7.0

<#
.SYNOPSIS
    Framework de Manutenção Preventiva, Atualização e Otimização para Windows 10 e 11.

.DESCRIPTION
    Este script orquestra um conjunto de funções organizadas em etapas cronológicas para:
	Executa funções específicas para cada fase:
		Fase 1	- Invetário de Hardware e Software
		Fase 2	- Integridade do sistema
		Fase 3	- Otimizações estruturais
		Fase 4	- Limpeza de arquivos temporários
		Fase 5	- Atualizações controladas
		Fase 6	- Pós-atualização / Componentes
		Fase 7	- Otimização de Armazenamento
		Fase 8	- Segurança (Varredura contra malwares)
		Fase 9	- Gestão (Centralização de logs no Servidor de Arquivos)
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
    IT4You Ltda
.VERSION
    1.6
.LASTUPDATED
    12/01/2026
#>


[CmdletBinding()]
param(
  [int[]]$ExecutaFases,  # Se não for informado, executa todas as fases
  [int[]]$PulaFases,     # Se não for informado, nenhuma fase será pulada
  [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$LogLevel = 'INFO',
  [switch]$Simulado,     # Modo ensaio: não executa ações destrutivas
  [string]$FileServer,   # Host/IP do servidor de arquivos para envio do log (opcional)
  [string]$Cliente       # Nome do nosso Cliente (preferencialmente, nome da Empresa onde ele trabalha)
)

if ([string]::IsNullOrWhiteSpace($Cliente)) {
    $Cliente = 'Cliente não identificado'
}


# --- BLOCO DE ELEVAÇÃO E DETECÇÃO DO POWERSHELL 7 ---
# Se não estiver como Admin, reinicia com privilégios elevados
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


# ✅ Ajusta os parâmetros
$ExecutaFases = Ajusta-Fases $ExecutaFases
$PulaFases    = Ajusta-Fases $PulaFases

# Remove duplicados e ordena
$ExecutaFases = $ExecutaFases | Sort-Object -Unique
$PulaFases    = $PulaFases | Sort-Object -Unique

# Log para confirmar
Write-Host "ExecutaFases ajustado: $($ExecutaFases -join ', ')"
Write-Host "PulaFases ajustado: $($PulaFases -join ', ')"

#endregion


# Preferências e ambiente
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Caminhos
$root    = Split-Path -Parent $PSCommandPath
$funcDir = Join-Path $root 'Functions'

# Início: Ajuste Mínimo de Pasta/Arquivo de Log
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
# Fim: Ajuste Mínimo de Pasta/Arquivo de Log





# === Verificação de execução recente (último log) ===
if (Test-Path $logDir) {
    $ultimoLog = Get-ChildItem -Path $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($ultimoLog) {
        $horasDesdeUltimoLog = (New-TimeSpan -Start $ultimoLog.LastWriteTime -End (Get-Date)).TotalHours
        if ($horasDesdeUltimoLog -lt 48) {
            #Write-Host "Última execução foi há $([math]::Round($horasDesdeUltimoLog,2)) horas. Saindo sem executar nada." -ForegroundColor Yellow
            #exit 0
        }
    }
}
# ================================================





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
  'Update-WindowsOS'         = 'Atualização do Windows'
  'Update-MicrosoftStore'    = 'Atualização da Loja da Microsoft'
  'Update-WingetApps'        = 'Atualização dos programas instalados via Winget'
  'Remove-OldUpdateFiles'    = 'Limpeza dos arquivos temporários dos componentes do Windows'
  'Optimize-SSD'             = 'Otimização de todos os SSDs disponíveis'
  'Optimize-HDD'             = 'Desfragmentação de todos os discos físicos disponíveis'
  'Scan-AntiMalware'         = 'Varredura contra malwares com Windows Defender'
  'Confirm-MacriumBackup'    = 'Validação dos arquivos de backup do Macrium Reflect'
  'Send-LogToServer'         = 'Verificação e centralização do log no Servidor de Arquivos (opcional com -FileServer)'
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
    if ($global:CurrentStepTitle -eq 'Get-SystemInventory') {
      if ($Message -match '^Iniciando:' -or $Message -match '^Informações do Inventário' -or $Message -eq '') {
        $shouldWriteRawToFile = $false
      } else {
        $shouldWriteRawToFile = $true
        $rawToWrite = $Message
      }
    }
  } else {
    $shouldWriteRawToFile = $false
  }

  if ($shouldWriteRawToFile) {
    Write-Report -Text $rawToWrite
  } elseif (-not $global:ConciseLog) {
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
  }

  switch ($Level) {
    'ERROR' { Write-Host ("{0}[ALERTA]{1} {2}" -f $Yellow, $Reset, $Message) }
    'WARN'  { Write-Host ("{0}[AVISO]{1}  {2}" -f $Yellow, $Reset, $Message) }
    'DEBUG' { Write-Host ("{0}[DEBUG]{1}  {2}" -f $Gray,   $Reset, $Message) }
    default { Write-Host (""  -f $Gray,   $Reset, $Message) }
  }
}

#function Show-Header {
#  param([string]$Text)
#  $bar = '─' * ($Text.Length + 2)
#  Write-Host ("{0}┌{1}┐{2}" -f $Cyan, $bar, $Reset)
#  Write-Host ("{0}│ {1} │{2}" -f $Cyan, $Text, $Reset)
#  Write-Host ("{0}└{1}┘{2}" -f $Cyan, $bar, $Reset)
#}


function Show-Header {
    param(
        [string]$Text,
        [string]$Color = $Cyan  # Cor padrão é a mesma que você já usa
    )

    $bar = '─' * ($Text.Length + 2)
    Write-Host ("{0}┌{1}┐{2}" -f $Color, $bar, $Reset)
    Write-Host ("{0}│ {1} │{2}" -f $Color, $Text, $Reset)
    Write-Host ("{0}└{1}┘{2}" -f $Color, $bar, $Reset)
}


function Show-Phase {
  param([int]$Id,[string]$Title)
  Write-Host ""
  Write-Host ""
  Write-Host ("{0}► Fase {1}:{2} {3}" -f $Cyan, $Id, $Reset, $Title)
}

function Show-StepStart { param([string]$Name) Write-Host ("  {0}•{1} Iniciando: {2} ..." -f $Gray, $Reset, $Name) }

function Show-StepEnd {
  param([string]$Name,[TimeSpan]$Elapsed,[bool]$Ok)
  if ($Ok) {
    Write-Host ("  {0}►{1} {2} concluída com sucesso em {3}" -f $Green, $Reset, $Name, (Format-Elapsed $Elapsed))
  } else {
    Write-Host ("  {0}!{1} {2} finalizada com alertas (veja o log). Tempo: {3}" -f $Yellow, $Reset, $Name, (Format-Elapsed $Elapsed))
  }
}

function Test-IsAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

function Test-AdminOrExit {
  if (-not (Test-IsAdmin)) {
    Show-Header -Text 'Permissão insuficiente'
    Write-Log "A execução requer privilégios administrativos. Agende como Admin/SYSTEM. Encerrando." 'ERROR'
    Pause
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
  Write-Log    ("Guardian ({0})" -f $dataHoraFormatada) 'INFO'
  Write-Log "____________________________________________________________________________________________________________________________________"
  Write-Report ("Guardian ({0})" -f $dataHoraFormatada)
  Write-Report "____________________________________________________________________________________________________________________________________"
}

function Stop-Logging { Write-Log 'Fim da execução Guardian' 'INFO' }

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

function Invoke-QuickEditLog { param([string]$Message, [string]$Level = 'INFO') try { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level } } catch {} }

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

function Invoke-ConsoleLog { param([string]$Message,[string]$Level='DEBUG') try { if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Message $Level } } catch {} }
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

# 1) Pré-requisitos para o Script poder rodar corretamente (sem prompts)
Test-AdminOrExit
Initialize-Pwsh7
Enable-QuickEditProtection
Enable-ConsoleAppearance -ForceMaximize
Start-Logging
Clear-Host
Show-Header -Text 'Guardian 360 — Manutenção e Otimização'

try {
  # 2) Carregar funções do repositório
  $functionFiles = @(
    'Show-GuardianUI.ps1',
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
    'Show-GuardianEndUI.ps1'
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

  
  # Garante que sempre teremos um array, mesmo se a função retornar $null
 
# Garante que sempre teremos um array, mesmo se a função retornar $null
$disks = @(Get-PhysicalDisksByType)

# Cria listas separadas para SSD e HDD
$ssdList = @($disks | Where-Object { $_.MediaType -match 'SSD' })
$hddList = @($disks | Where-Object { $_.MediaType -match 'HDD|Unspecified' })

# Flags seguras
$hasSSD = ($ssdList.Count -gt 0)
$hasHDD = ($hddList.Count -gt 0)





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
        #@{ Name='Clear-BrowserCache';        Action={ Clear-BrowserCache } },
        @{ Name='Clear-WindowsUpdateCache';  Action={ Clear-WindowsUpdateCache } },
        @{ Name='Clear-TempFiles';           Action={ Clear-TempFiles } },
        @{ Name='Clear-AllRecycleBins';      Action={ Clear-AllRecycleBins } }
        #@{ Name='Clear-RecentFilesHistory';  Action={ Clear-RecentFilesHistory } }
      )},
    @{ Id=5; Title='Atualizações Controladas'; Steps=@(
        @{ Name='Update-WindowsOS'; Action={ if($hasInet){ Update-WindowsOS } else { Write-Log 'Sem internet: pulando Update-WindowsOS' 'WARN' } } },
        @{ Name='Update-MicrosoftStore'; Action={ if($hasInet){ Update-MicrosoftStore } else { Write-Log 'Sem internet: pulando Update-MicrosoftStore' 'WARN' } } },
        @{ Name='Update-WingetApps';    Action={ if($hasInet){ Update-WingetApps } else { Write-Log 'Sem internet: pulando Update-WingetApps' 'WARN' } } }
        
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
      )}
  )


  # Incício do Cronômetro do Script
  $scriptStart = [Diagnostics.Stopwatch]::StartNew()


  # Exibe a UI amigável enquanto o script continua rodand
  # Show-GuardianUI
  Show-GuardianUI | Out-Null
  


# Adicione no início do script:
Add-Type -AssemblyName System.Windows.Forms

function DoEvents {
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}


# Adicione no início do script (após definir $Phases):
Add-Type -AssemblyName System.Windows.Forms

function DoEvents {
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}

# === Cálculo do total de passos que serão executados ===
$TotalSteps = 0
foreach ($phase in $Phases) {
    $id = [int]$phase.Id
    if ($ExecutaFases -and ($ExecutaFases -notcontains $id)) { continue }
    if ($PulaFases -and ($PulaFases -contains $id)) { continue }

    # Garante que Steps seja tratado como array
    $steps = @($phase.Steps)
    $TotalSteps += $steps.Count
}


# Ajusta a barra de progresso para refletir isso
if ($global:GuardianProgressBar) {
    $global:GuardianProgressBar.Dispatcher.Invoke({
        $global:GuardianProgressBar.Minimum = 0
        $global:GuardianProgressBar.Maximum = $TotalSteps
        $global:GuardianProgressBar.Value = 0
    })
}

# Contador de passos concluídos
$CurrentStep = 0


 Write-Host ""
 Write-Host ("► Cliente: {0}{1}{2}" -f $Cyan, $Cliente, $Reset)

 Write-Report ""
 Write-Report ("Cliente: {0}" -f $Cliente)


# === Loop principal com atualização da UI ===
foreach ($phase in $Phases) {
    $id = [int]$phase.Id
    if ($ExecutaFases -and ($ExecutaFases -notcontains $id)) { continue }
    if ($PulaFases -and ($PulaFases -contains $id)) { continue }

    # Atualiza UI com fase atual
    if ($global:GuardianPhaseText) {
        $global:GuardianPhaseText.Dispatcher.Invoke({
            $global:GuardianPhaseText.Text = "Fase ${id}: $($phase.Title)"
        })
    }

    DoEvents

    Write-Host ""
    Write-Host "=================================================================================================" -ForegroundColor DarkGray
    Show-Phase -Id $phase.Id -Title $phase.Title
    Write-Log ("=== Fase {0}: {1} ===" -f $phase.Id, $phase.Title) 'INFO'

    # Executa cada passo da fase
    foreach ($step in $phase.Steps) {
        # Atualiza UI com nome do passo atual e progresso
        $CurrentStep++
        if ($global:GuardianPhaseText) {
            $global:GuardianPhaseText.Dispatcher.Invoke({
                $global:GuardianPhaseText.Text = "Fase ${id}: $($phase.Title)`nExecutando: $($step.Name)`nProgresso: $CurrentStep de $TotalSteps"
            })
        }

        DoEvents

        # Executa o passo
        Invoke-GuardianStep -Title $step.Name -Action $step.Action

        # Atualiza barra de progresso proporcional
        if ($global:GuardianProgressBar) {
            $global:GuardianProgressBar.Dispatcher.Invoke({
                $global:GuardianProgressBar.Value = $CurrentStep
            })
        }

        DoEvents
    }

    #if ($id -eq 5 -and (Get-RebootPending)) {
    #    Write-Log 'Reinicialização pendente detectada após Atualizações.' 'WARN'
    #    Write-Host ("{0}› Uma reinicialização está pendente. Ela pode ser realizada fora desta janela de manutenção.{1}" -f $Yellow, $Reset)
    #}
}






  # 6) Resumo final
  Write-Host ""
  Write-Host "=================================================================================================" -ForegroundColor DarkGray
  Write-Host ""
  Show-Header -Text 'Resumo da Manutenção Automatizada'
  Write-Host ""

  #Write-Host ("Cliente: {0}{1}{2}" -f $Cyan, $Cliente, $Reset)
  #Write-Host ""
  
  $maxLabel = 0
  foreach ($r in $global:Results) { if ($r.Etapa.Length -gt $maxLabel) { $maxLabel = $r.Etapa.Length } }

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

  Write-Host ""
  Write-Report ""
  Confirm-MacriumBackup


 
# Finalização do Cronômetro do Script
$scriptStart.Stop()
$global:tempoFormatado = Format-Elapsed $scriptStart.Elapsed
Write-Host ""
Write-Host ("{0}PS.:{1} Duração total da execução do script de manutenção automatizada: {2}{3}" -f $Gray, $Reset, $tempoFormatado, $Reset)
Write-Report ""
Write-Report ("Duração total da execução do script de manutenção automatizada: {0}" -f $tempoFormatado)

Write-Host ""
Write-Host ("{0}Arquivo de log:{1} {2}" -f $Gray, $Reset, $logFile)
Write-Host ""
Write-Report ""
Write-Report ("Arquivo de log: {0}" -f $logFile)


Write-Host ""
Write-Host "=================================================================================================" -ForegroundColor DarkGray

# Fecha a tela gráfica do Guardian ao terminar o script, se estiver aberta

if ($global:GuardianUIWindow) {
    try {
        $global:GuardianUIWindow.Close()
    } catch {
        Write-Log "Falha ao fechar a UI: $($_.Exception.Message)" 'WARN'
    }
}


  # Exibe a UI amigável enquanto o script continua rodand
  Show-GuardianEndUI | Out-Null


# Pausa breve para garantir que a UI feche antes do término do script
Start-Sleep -Milliseconds 500



#region Envio do Log para Servidor de Arquivos
if ($PSBoundParameters.ContainsKey('FileServer')) {
    Send-LogToServer -Server $FileServer
}
#endregion







} catch {
  Write-Log ("FALHA GERAL (capturada): {0}" -f $_.ToString()) 'ERROR'
} finally {
  Disable-QuickEditProtection
  Disable-ConsoleAppearance
  Stop-Logging
}