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
  [int[]]$ExecutaFases,  # Se não informado, executa todas as fases
  [int[]]$PulaFases,     # Se não informado, nenhuma fase é pulada
  [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$LogLevel = 'INFO',
  [switch]$Simulado      # Modo ensaio: não executa ações destrutivas
)

Clear-Host

# Preferências e ambiente
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Caminhos
$root    = Split-Path -Parent $PSCommandPath
$funcDir = Join-Path $root 'Functions'
$logDir  = Join-Path $root 'Logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $logDir "Guardian360-$stamp.log"
$transcriptFile = Join-Path $logDir "Transcript-$stamp.txt"

# TLS forte (sem prompts)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {}

# Resultados agregados
$global:Results = New-Object System.Collections.Generic.List[object]

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

function Write-Log {
  param([string]$Message,[ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level='INFO')
  $levelsPriority = @{ 'ERROR'=3; 'WARN'=2; 'INFO'=1; 'DEBUG'=0 }
  if ($levelsPriority[$Level] -lt $levelsPriority[$LogLevel]) { return }
  $line = "[{0:u}] [{1}] {2}" -f (Get-Date), $Level, $Message
  $line | Out-File -FilePath $logFile -Append -Encoding UTF8
  # Console amigável (sem “erros vermelhos” do PowerShell)
  switch ($Level) {
    'ERROR' { Write-Host ("{0}[ALERTA]{1} {2}" -f $Yellow, $Reset, $Message) }
    'WARN'  { Write-Host ("{0}[AVISO]{1}  {2}" -f $Yellow, $Reset, $Message) }
    'DEBUG' { Write-Host ("{0}[DEBUG]{1}  {2}" -f $Gray,   $Reset, $Message) }
    #default { Write-Host ("{0}[INFO]{1}   {2}"  -f $Gray,   $Reset, $Message) }
    default { Write-Host (""  -f $Gray,   $Reset, $Message) }
  }
}

function Show-Header {
  param([string]$Text)
  $bar = '─' * ($Text.Length + 2)
  Write-Host ""
  Write-Host ("{0}┌{1}┐{2}" -f $Cyan, $bar, $Reset)
  Write-Host ("{0}│ {1} │{2}" -f $Cyan, $Text, $Reset)
  Write-Host ("{0}└{1}┘{2}" -f $Cyan, $bar, $Reset)
}

function Show-Phase {
  param([int]$Id,[string]$Title)
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
    Write-Host ("    {0}✓{1} {2} concluído com sucesso em {3}" -f $Green, $Reset, $Name, (Format-Elapsed $Elapsed))
  } else {
    Write-Host ("    {0}!{1} {2} finalizado com alertas (veja o log). Tempo: {3}" -f $Yellow, $Reset, $Name, (Format-Elapsed $Elapsed))
  }
}

function Test-IsAdmin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# VERBO APROVADO: Test-
function Test-AdminOrExit {
  if (-not (Test-IsAdmin)) {
    Show-Header -Text 'Permissão insuficiente'
    Write-Log "A execução requer privilégios administrativos. Agende como Admin/SYSTEM. Encerrando." 'ERROR'
    exit 1
  }
}

# VERBO APROVADO: Initialize-
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
  try { Start-Transcript -Path $transcriptFile -Append | Out-Null } catch {}
  Write-Log ("Início da execução Guardian360 ({0})" -f $stamp) 'INFO'
}
function Stop-Logging {
  Write-Log 'Fim da execução Guardian360' 'INFO'
  try { Stop-Transcript | Out-Null } catch {}
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
  return ,$list  # vírgula garante retorno como array
}

function Format-Elapsed {
  param([TimeSpan]$Elapsed)
  $min = [int][Math]::Floor($Elapsed.TotalMinutes)
  $sec = $Elapsed.Seconds
  return ('{0:00} min {1:00} seg' -f $min, $sec)
}

function Invoke-GuardianStep {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][scriptblock]$Action
  )
  Write-Log ("Iniciando: {0}" -f $Title) 'INFO'
  Show-StepStart -Name $Title
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $ok = $true
  try {
    if ($Simulado) {
      Write-Log ("SIMULADO: ação não executada para '{0}'." -f $Title) 'DEBUG'
    } else {
      & $Action
    }
  } catch {
    $ok = $false
    Write-Log ("Etapa '{0}' registrou erro: {1}" -f $Title, $_.ToString()) 'ERROR'
  }
  $sw.Stop()
  $global:Results.Add([pscustomobject]@{ Etapa=$Title; Sucesso=$ok; Tempo=$sw.Elapsed })
  Show-StepEnd -Name $Title -Elapsed $sw.Elapsed -Ok:$ok
}

# 1) Pré-requisitos (sem prompts)
Test-AdminOrExit
Initialize-Pwsh7
Start-Logging
Show-Header -Text 'Guardian360 — Manutenção e Otimização'



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
        'Validate-MacriumBackup.ps1',
        'Send-LogToServer.ps1'
    )

    foreach ($ff in $functionFiles) {
        $path = Join-Path $funcDir $ff
        if (-not (Test-Path $path)) {
            Write-Log ("Arquivo de função não encontrado: {0}" -f $path) 'ERROR'
            continue
        }
        try {
            . $path
        } catch {
            Write-Log ("Falha ao carregar {0}: {1}" -f $ff, $_.ToString()) 'ERROR'
        }
    }

    # 3) Detectores de cenário
    $hasInet = Test-Internet
    $disks   = Get-PhysicalDisksByType
    $hasSSD  = @($disks | Where-Object { $_.MediaType -match 'SSD' }).Count -gt 0
    $hasHDD  = @($disks | Where-Object { $_.MediaType -match 'HDD|Unspecified' }).Count -gt 0

    # 4) Fases e passos
    $Phases = @(
        @{ Id=1; Title='Inventário de Hardware e Software'; Steps=@(
            @{ Name='Get-SystemInventory'; Action={ Get-SystemInventory } }
        )},
        @{ Id=2; Title='Integridade do Sistema'; Steps=@(
            @{ Name='Repair-SystemIntegrity'; Action={ Repair-SystemIntegrity } }
        )},
        @{ Id=3; Title='Otimizações Estruturais'; Steps=@(
            @{ Name='Optimize-PowerSettings'; Action={ Optimize-PowerSettings } },
            @{ Name='Optimize-NetworkSettings'; Action={ Optimize-NetworkSettings } }
        )},
        @{ Id=4; Title='Limpeza de arquivos temporários'; Steps=@(
            @{ Name='Clear-BrowserCache'; Action={ Clear-BrowserCache } },
            @{ Name='Clear-AllRecycleBins'; Action={ Clear-AllRecycleBins } },
            @{ Name='Clear-TempFiles'; Action={ Clear-TempFiles } },
            @{ Name='Clear-WindowsUpdateCache'; Action={ Clear-WindowsUpdateCache } },
            @{ Name='Clear-RecentFilesHistory'; Action={ Clear-RecentFilesHistory } }
        )},
        @{ Id=5; Title='Atualizações Controladas'; Steps=@(
            @{ Name='Update-WingetApps'; Action={ if($hasInet){ Update-WingetApps } else { Write-Log 'Sem internet: pulando Update-WingetApps' 'WARN' } } },
            @{ Name='Update-ChocoApps'; Action={ if($hasInet){ Update-ChocoApps } else { Write-Log 'Sem internet: pulando Update-ChocoApps' 'WARN' } } }
        )},
        @{ Id=6; Title='Pós-atualização / Componentes'; Steps=@(
            @{ Name='Remove-OldUpdateFiles'; Action={ Remove-OldUpdateFiles } }
        )},
        @{ Id=7; Title='Otimização de Armazenamento'; Steps=@(
            @{ Name='Optimize-SSD'; Action={ if($hasSSD){ Optimize-SSD } else { Write-Log 'Nenhum SSD detectado: pulando Optimize-SSD' 'INFO' } } },
            @{ Name='Optimize-HDD'; Action={ if($hasHDD){ Optimize-HDD } else { Write-Log 'Nenhum HDD detectado: pulando Optimize-HDD' 'INFO' } } }
        )},
        @{ Id=8; Title='Segurança'; Steps=@(
            @{ Name='Scan-AntiMalware'; Action={ Scan-AntiMalware } },
            @{ Name='Validate-MacriumBackup'; Action={ Validate-MacriumBackup } }
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

        Show-Phase -Id $phase.Id -Title $phase.Title
        Write-Log ("=== Fase {0}: {1} ===" -f $phase.Id, $phase.Title) 'INFO'

        foreach ($step in $phase.Steps) {
            Invoke-GuardianStep -Title $step.Name -Action $step.Action
        }

        # Pós-fase 5: aviso de reboot pendente
        if ($id -eq 5 -and (Get-RebootPending)) {
            Write-Log 'Reinicialização pendente detectada após Atualizações.' 'WARN'
            Write-Host ("{0}› Uma reinicialização está pendente. Ela pode ser realizada fora desta janela de manutenção.{1}" -f $Yellow, $Reset)
        }
    }

    # 6) Resumo final
    Write-Host ""
    Show-Header -Text 'Resumo da Execução'
    foreach ($r in $global:Results) {
        $status = if ($r.Sucesso) { "{0}OK{1}" -f $Green, $Reset } else { "{0}ALERTA{1}" -f $Yellow, $Reset }
        Write-Host ("- {0} -> {1} (Tempo: {2})" -f $r.Etapa, $status, (Format-Elapsed $r.Tempo))
    }
    Write-Host ""
    Write-Host ("{0}Arquivo de log:{1} {2}" -f $Gray, $Reset, $logFile)
    Write-Host ("{0}Transcript:{1}      {2}" -f $Gray, $Reset, $transcriptFile)

} catch {
    # Nunca mostrar erro “vermelho” de PowerShell na tela
    Write-Log ("FALHA GERAL (capturada): {0}" -f $_.ToString()) 'ERROR'
} finally {
    Stop-Logging
}


