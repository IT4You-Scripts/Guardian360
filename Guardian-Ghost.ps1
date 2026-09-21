#Requires -Version 7.0

<#
.SYNOPSIS
    Guardian Ghost - Fase 2 silenciosa (System Integrity)
.DESCRIPTION
    Executa o Repair-SystemIntegrity (DISM + SFC) de forma totalmente silenciosa,
    desvinculado do Guardian principal. Roda como SYSTEM via Agendador de Tarefas.
    Controle de execucao via guardian_ghost.json (1x por mes).
.AUTHOR
    Tato, IT4You Ltda
.VERSION
    1.0
#>

# ============================================================================
# CONFIGURACAO
# ============================================================================
$GhostJsonPath = "C:\Guardian\guardian_ghost.json"
$FuncDir       = "C:\Guardian\Functions"

# ============================================================================
# VERIFICACAO: ja rodou este mes?
# ============================================================================
if (Test-Path $GhostJsonPath) {
    try {
        $ghostData = Get-Content $GhostJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ghostData.ultima_execucao) {
            $ultimaExecucao = [datetime]::Parse($ghostData.ultima_execucao)
            $agora = Get-Date

            # Se ja rodou no mesmo mes e ano, aborta
            if ($ultimaExecucao.Year -eq $agora.Year -and $ultimaExecucao.Month -eq $agora.Month) {
                exit 0
            }
        }
    }
    catch {
        # Se o JSON estiver corrompido, ignora e executa
    }
}

# ============================================================================
# ELEVACAO E POWERSHELL 7
# ============================================================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $pwshPath = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
        if ($pwshPath) {
            Start-Process $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Hidden
        }
        exit
    } catch {
        exit 1
    }
}

# ============================================================================
# FUNCAO WRITE-LOG SIMPLIFICADA (para compatibilidade com Repair-SystemIntegrity)
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    # Silencioso — nao grava nada, apenas satisfaz a chamada
}

# ============================================================================
# PADRONIZAR RETENCAO DO MACRIUM REFLECT
# Mesma logica validada isoladamente executando como SYSTEM.
# Nao cria a chave Defaults; altera somente perfis que ja possuem configuracao.
# ============================================================================
$desiredMacrium = [ordered]@{
    FullRetention  = 1
    FullPeriod     = 0
    FullInterval   = 1
    DiffRetention  = 0
    PurgeBefore    = 1
    PurgeOldest    = 0
    PurgeThreshold = 5
}

$profileListMacrium = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$profilesMacrium = Get-ChildItem -LiteralPath $profileListMacrium -ErrorAction SilentlyContinue

foreach ($profileMacrium in $profilesMacrium) {
    $sidMacrium = $profileMacrium.PSChildName

    if ($sidMacrium -notmatch '^S-1-5-21-.+-\d+$') {
        continue
    }

    try {
        $profileInfoMacrium = Get-ItemProperty -LiteralPath $profileMacrium.PSPath -ErrorAction Stop
        $profilePathMacrium = [Environment]::ExpandEnvironmentVariables(
            [string]$profileInfoMacrium.ProfileImagePath
        )
    }
    catch {
        continue
    }

    if (-not (Test-Path -LiteralPath $profilePathMacrium)) {
        continue
    }

    $rootMacrium = "Registry::HKEY_USERS\$sidMacrium"
    $tempHiveNameMacrium = $null
    $loadedByUsMacrium = $false

    try {
        if (-not (Test-Path -LiteralPath $rootMacrium)) {
            $ntUserMacrium = Join-Path $profilePathMacrium 'NTUSER.DAT'

            if (-not (Test-Path -LiteralPath $ntUserMacrium)) {
                continue
            }

            $safeSidMacrium = $sidMacrium -replace '[^A-Za-z0-9_-]', '_'
            $tempHiveNameMacrium = "GuardianMacrium_$safeSidMacrium"

            & reg.exe load "HKU\$tempHiveNameMacrium" "$ntUserMacrium" 2>&1 | Out-Null
            $loadExitMacrium = $LASTEXITCODE

            if ($loadExitMacrium -ne 0) {
                continue
            }

            $rootMacrium = "Registry::HKEY_USERS\$tempHiveNameMacrium"
            $loadedByUsMacrium = $true
        }

        $defaultsPathMacrium = "$rootMacrium\SOFTWARE\Macrium\reflect\Defaults"

        if (-not (Test-Path -LiteralPath $defaultsPathMacrium)) {
            continue
        }

        foreach ($nameMacrium in $desiredMacrium.Keys) {
            $targetMacrium = [int]$desiredMacrium[$nameMacrium]

            try {
                New-ItemProperty `
                    -LiteralPath $defaultsPathMacrium `
                    -Name $nameMacrium `
                    -Value $targetMacrium `
                    -PropertyType DWord `
                    -Force `
                    -ErrorAction Stop | Out-Null
            }
            catch {
                # Uma falha de valor nao impede os demais nem o Ghost.
            }
        }
    }
    finally {
        if ($loadedByUsMacrium -and $tempHiveNameMacrium) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            & reg.exe unload "HKU\$tempHiveNameMacrium" 2>&1 | Out-Null
        }
    }
}

# ============================================================================
# CARREGAR E EXECUTAR REPAIR-SYSTEMINTEGRITY
# ============================================================================
try {
    $repairPath = Join-Path $FuncDir "Repair-SystemIntegrity.ps1"
    if (-not (Test-Path $repairPath)) {
        exit 1
    }

    . $repairPath
    Repair-SystemIntegrity

    # ========================================================================
    # SUCESSO: Gravar guardian_ghost.json
    # ========================================================================
    $resultado = @{
        ultima_execucao = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $resultado | ConvertTo-Json | Set-Content -Path $GhostJsonPath -Encoding UTF8 -Force

} catch {
    # Falha silenciosa — nao interrompe nada
    exit 1
}

exit 0
